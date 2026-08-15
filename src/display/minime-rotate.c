/*
 * minime-rotate: set or query the DRM/KMS primary-plane rotation on the
 * internal (non-HDMI) connector. Used by init.d/display to apply the
 * per-device `screen_rotation_kernel` trait in hardware on SoCs whose
 * display controller has a rotation unit (RK3566 VOP2).
 *
 *   minime-rotate --query             print internal connector/plane state
 *   minime-rotate [--device PATH] N   set primary-plane rotation to N degrees
 *                                     (0, 90, 180 or 270)
 */

#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#ifndef DRM_MODE_CONNECTED
#define DRM_MODE_CONNECTED 1
#endif
#ifndef DRM_PLANE_TYPE_PRIMARY
#define DRM_PLANE_TYPE_PRIMARY 1
#endif

static uint32_t rot_for_angle(int angle) {
	switch (angle) {
	case 90:  return DRM_MODE_ROTATE_90;
	case 180: return DRM_MODE_ROTATE_180;
	case 270: return DRM_MODE_ROTATE_270;
	default:  return DRM_MODE_ROTATE_0;
	}
}

static unsigned int angle_for_rot(uint64_t rot) {
	switch (rot & 0x0fU) {
	case DRM_MODE_ROTATE_90:  return 90;
	case DRM_MODE_ROTATE_180: return 180;
	case DRM_MODE_ROTATE_270: return 270;
	default:                  return 0;
	}
}

static int is_internal(uint32_t type) {
	switch (type) {
	case DRM_MODE_CONNECTOR_DSI:
	case DRM_MODE_CONNECTOR_eDP:
	case DRM_MODE_CONNECTOR_LVDS:
	case DRM_MODE_CONNECTOR_DPI:
		return 1;
	default:
		return 0;
	}
}

static const char *connector_name(uint32_t type) {
	switch (type) {
	case DRM_MODE_CONNECTOR_DSI:          return "DSI";
	case DRM_MODE_CONNECTOR_eDP:          return "eDP";
	case DRM_MODE_CONNECTOR_LVDS:         return "LVDS";
	case DRM_MODE_CONNECTOR_DPI:          return "DPI";
	case DRM_MODE_CONNECTOR_HDMIA:        return "HDMI-A";
	case DRM_MODE_CONNECTOR_HDMIB:        return "HDMI-B";
	case DRM_MODE_CONNECTOR_DisplayPort:  return "DP";
	default:                              return "unknown";
	}
}

static int get_obj_props(int fd, uint32_t obj_id, uint32_t obj_type,
			 uint32_t **ids_out, uint64_t **vals_out, uint32_t *count_out) {
	struct drm_mode_obj_get_properties req = {0};
	uint32_t *ids;
	uint64_t *vals;

	req.obj_id = obj_id;
	req.obj_type = obj_type;
	if (ioctl(fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &req) < 0 || req.count_props == 0)
		return -1;

	ids = calloc(req.count_props, sizeof(uint32_t));
	vals = calloc(req.count_props, sizeof(uint64_t));
	if (!ids || !vals) {
		free(ids);
		free(vals);
		return -1;
	}
	req.props_ptr = (uint64_t)(uintptr_t)ids;
	req.prop_values_ptr = (uint64_t)(uintptr_t)vals;
	if (ioctl(fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &req) < 0) {
		free(ids);
		free(vals);
		return -1;
	}

	*ids_out = ids;
	*vals_out = vals;
	*count_out = req.count_props;
	return 0;
}

static int find_prop(int fd, uint32_t obj_id, uint32_t obj_type,
		     const char *wanted, uint32_t *prop_id_out, uint64_t *val_out) {
	uint32_t *ids, *vals = NULL;
	uint32_t count = 0;
	int found = -1;

	/* get_obj_props returns uint64_t* values */
	if (get_obj_props(fd, obj_id, obj_type, &ids, (uint64_t **)&vals, &count) < 0)
		return -1;

	for (uint32_t i = 0; i < count; i++) {
		struct drm_mode_get_property prop = {0};
		prop.prop_id = ids[i];
		if (ioctl(fd, DRM_IOCTL_MODE_GETPROPERTY, &prop) < 0)
			continue;
		if (strcmp(prop.name, wanted) == 0) {
			*prop_id_out = ids[i];
			*val_out = ((uint64_t *)vals)[i];
			found = 0;
			break;
		}
	}
	free(ids);
	free(vals);
	return found;
}

static int find_internal_connector(int fd, uint32_t *conn_id_out, uint32_t *crtc_id_out) {
	struct drm_mode_card_res res = {0};
	uint32_t *ids;
	int found = -1;

	if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0 || res.count_connectors == 0)
		return -1;
	ids = calloc(res.count_connectors, sizeof(uint32_t));
	if (!ids)
		return -1;
	res.connector_id_ptr = (uint64_t)(uintptr_t)ids;
	if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
		free(ids);
		return -1;
	}

	for (uint32_t i = 0; i < res.count_connectors; i++) {
		struct drm_mode_get_connector conn = {0};
		struct drm_mode_get_encoder enc = {0};

		conn.connector_id = ids[i];
		if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn) < 0)
			continue;
		if (conn.connection != DRM_MODE_CONNECTED || !is_internal(conn.connector_type))
			continue;

		enc.encoder_id = conn.encoder_id;
		if (ioctl(fd, DRM_IOCTL_MODE_GETENCODER, &enc) < 0)
			continue;
		if (enc.crtc_id == 0)
			continue;

		*conn_id_out = ids[i];
		*crtc_id_out = enc.crtc_id;
		found = 0;
		break;
	}
	free(ids);
	return found;
}

static int find_primary_plane(int fd, uint32_t crtc_id, uint32_t *plane_id_out) {
	struct drm_mode_get_plane_res pres = {0};
	uint32_t *ids;
	int found = -1;

	if (ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &pres) < 0 || pres.count_planes == 0)
		return -1;
	ids = calloc(pres.count_planes, sizeof(uint32_t));
	if (!ids)
		return -1;
	pres.plane_id_ptr = (uint64_t)(uintptr_t)ids;
	if (ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &pres) < 0) {
		free(ids);
		return -1;
	}

	for (uint32_t i = 0; i < pres.count_planes; i++) {
		struct drm_mode_get_plane pl = {0};
		uint32_t prop_id;
		uint64_t type;

		pl.plane_id = ids[i];
		if (ioctl(fd, DRM_IOCTL_MODE_GETPLANE, &pl) < 0)
			continue;
		if (pl.crtc_id != crtc_id)
			continue;
		if (find_prop(fd, ids[i], DRM_MODE_OBJECT_PLANE, "type",
			      &prop_id, &type) < 0 || type != DRM_PLANE_TYPE_PRIMARY)
			continue;

		*plane_id_out = ids[i];
		found = 0;
		break;
	}
	free(ids);
	return found;
}

static int plane_supports_rotation(int fd, uint32_t prop_id, uint64_t want) {
	struct drm_mode_get_property prop = {0};
	struct drm_mode_property_enum *enums;
	int ok = 0;

	prop.prop_id = prop_id;
	if (ioctl(fd, DRM_IOCTL_MODE_GETPROPERTY, &prop) < 0)
		return 0;
	enums = calloc(prop.count_enum_blobs, sizeof(struct drm_mode_property_enum));
	if (!enums)
		return 0;
	prop.enum_blob_ptr = (uint64_t)(uintptr_t)enums;
	if (ioctl(fd, DRM_IOCTL_MODE_GETPROPERTY, &prop) == 0) {
		for (uint32_t i = 0; i < prop.count_enum_blobs; i++) {
			if (enums[i].value == want) {
				ok = 1;
				break;
			}
		}
	}
	free(enums);
	return ok;
}

static int set_plane_rotation(int fd, uint32_t plane_id, uint32_t prop_id, uint64_t want) {
	struct drm_mode_atomic atom = {0};
	uint32_t objs[1] = { plane_id };
	uint32_t props[1] = { prop_id };
	uint64_t vals[1] = { want };

	atom.count_objs = 1;
	atom.objs_ptr = (uint64_t)(uintptr_t)objs;
	atom.props_ptr = (uint64_t)(uintptr_t)props;
	atom.prop_values_ptr = (uint64_t)(uintptr_t)vals;

	if (ioctl(fd, DRM_IOCTL_MODE_ATOMIC, &atom) < 0 && errno == EINVAL) {
		atom.flags = DRM_MODE_ATOMIC_ALLOW_MODESET;
		if (ioctl(fd, DRM_IOCTL_MODE_ATOMIC, &atom) < 0)
			return -1;
	}
	return 0;
}

static int query(int fd, const char *dev) {
	uint32_t conn_id = 0, crtc_id = 0, plane_id = 0, prop_id;
	uint64_t val;
	struct drm_mode_get_connector conn = {0};

	if (find_internal_connector(fd, &conn_id, &crtc_id) < 0) {
		fprintf(stderr, "minime-rotate: no active internal panel connector on %s\n", dev);
		return 1;
	}
	conn.connector_id = conn_id;
	ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn);
	printf("connector: %s (id %u), crtc %u\n",
	       connector_name(conn.connector_type), conn_id, crtc_id);

	if (find_prop(fd, conn_id, DRM_MODE_OBJECT_CONNECTOR, "panel orientation",
		      &prop_id, &val) == 0)
		printf("panel orientation: %llu\n", (unsigned long long)val);

	if (find_primary_plane(fd, crtc_id, &plane_id) < 0) {
		printf("primary plane: none active\n");
		return 0;
	}
	if (find_prop(fd, plane_id, DRM_MODE_OBJECT_PLANE, "rotation", &prop_id, &val) < 0) {
		printf("primary plane: id %u, no rotation property\n", plane_id);
		return 0;
	}
	printf("primary plane: id %u, rotation %u deg\n", plane_id, angle_for_rot(val));
	return 0;
}

int main(int argc, char **argv) {
	const char *dev = "/dev/dri/card0";
	int query_mode = 0;
	int angle = -1;
	int fd;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--query") == 0) {
			query_mode = 1;
		} else if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
			dev = argv[++i];
		} else if (argv[i][0] >= '0' && argv[i][0] <= '9') {
			angle = atoi(argv[i]);
		} else {
			fprintf(stderr, "usage: minime-rotate [--device PATH] (--query | 0|90|180|270)\n");
			return 1;
		}
	}

	fd = open(dev, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror("minime-rotate: open");
		return 1;
	}
	struct drm_set_client_cap cap_univ = { .capability = DRM_CLIENT_CAP_UNIVERSAL_PLANES, .value = 1 };
	ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &cap_univ);
	struct drm_set_client_cap cap_atomic = { .capability = DRM_CLIENT_CAP_ATOMIC, .value = 1 };
	ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &cap_atomic);

	if (query_mode) {
		int r = query(fd, dev);
		close(fd);
		return r;
	}

	if (angle != 0 && angle != 90 && angle != 180 && angle != 270) {
		fprintf(stderr, "minime-rotate: invalid angle %d (valid: 0, 90, 180, 270)\n", angle);
		close(fd);
		return 1;
	}

	uint32_t conn_id = 0, crtc_id = 0, plane_id = 0, prop_id;
	uint64_t cur;
	if (find_internal_connector(fd, &conn_id, &crtc_id) < 0) {
		fprintf(stderr, "minime-rotate: no active internal panel connector on %s\n", dev);
		close(fd);
		return 1;
	}
	if (find_primary_plane(fd, crtc_id, &plane_id) < 0) {
		fprintf(stderr, "minime-rotate: no active primary plane\n");
		close(fd);
		return 1;
	}
	if (find_prop(fd, plane_id, DRM_MODE_OBJECT_PLANE, "rotation", &prop_id, &cur) < 0) {
		fprintf(stderr, "minime-rotate: primary plane has no rotation property "
			       "(hardware rotation unsupported)\n");
		close(fd);
		return 1;
	}

	uint64_t want = rot_for_angle(angle);
	if (cur == want) {
		printf("rotation already %d deg\n", angle);
		close(fd);
		return 0;
	}
	if (!plane_supports_rotation(fd, prop_id, want)) {
		fprintf(stderr, "minime-rotate: primary plane does not support %d deg rotation\n", angle);
		close(fd);
		return 1;
	}
	if (set_plane_rotation(fd, plane_id, prop_id, want) < 0) {
		perror("minime-rotate: atomic commit");
		close(fd);
		return 1;
	}
	printf("set primary plane rotation to %d deg\n", angle);
	close(fd);
	return 0;
}
