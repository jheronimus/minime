// traits.c — Minime hardware traits reference implementation (parser).
//
// Pair this with traits.h (same directory). This is the canonical example of
// the strict schema-table parser: it reads /mnt/sdcard/.minime/traits into a
// MinimeTraitsRef struct and errors on unknown keys / missing required keys /
// malformed integers rather than silently guessing.
//
// Self-contained: libc only. No project-internal headers.
//
// The schema table below is the single list of known keys. If a future Minime
// release adds a key, add one row here and one field in the struct — nothing
// else changes. Porting teams should mirror this file rather than re-derive
// device knowledge in their UI code.

#include <ctype.h>
#include <dirent.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "traits.h"

#define NA "na"

typedef enum {
    TYPE_STRING,
    TYPE_INT,
    TYPE_ASPECT,
} TraitType;

typedef struct {
    const char *key;
    TraitType type;
    size_t offset;
} TraitField;

#define FIELD(type, name) {#name, type, offsetof(MinimeTraitsRef, name)}
#define STR_FIELD(name) FIELD(TYPE_STRING, name)
#define INT_FIELD(name) FIELD(TYPE_INT, name)
#define ASPECT_FIELD(name) FIELD(TYPE_ASPECT, name)

static const TraitField TRAIT_FIELDS[] = {
    STR_FIELD(device_id),
    STR_FIELD(device_model),
    INT_FIELD(screen_width),
    INT_FIELD(screen_height),
    INT_FIELD(screen_rotation),
    ASPECT_FIELD(screen_aspect),
    INT_FIELD(screen_refresh_rate),
    STR_FIELD(screen_backlight_path),
    INT_FIELD(screen_backlight_max),
    STR_FIELD(screen_blank_path),
    INT_FIELD(screen2_width),
    INT_FIELD(screen2_height),
    INT_FIELD(screen2_rotation),
    ASPECT_FIELD(screen2_aspect),
    INT_FIELD(screen2_refresh_rate),
    STR_FIELD(screen2_backlight_path),
    STR_FIELD(screen2_blank_path),
    INT_FIELD(screen2_touch),
    STR_FIELD(screen2_touch_device_name),
    STR_FIELD(cpu_governor_path),
    STR_FIELD(cpu_clock_path),
    INT_FIELD(cpu_clock_menu),
    INT_FIELD(cpu_clock_powersave),
    INT_FIELD(cpu_clock_normal),
    INT_FIELD(cpu_clock_performance),
    INT_FIELD(cpu_undervolt_supported),
    STR_FIELD(cpu_thermal_path),
    STR_FIELD(gpu_device),
    STR_FIELD(gpu_device2),
    STR_FIELD(gpu_hdmi_connector),
    STR_FIELD(gpu_driver),
    INT_FIELD(gpu_clock_min),
    INT_FIELD(gpu_clock_max),
    STR_FIELD(audio_card),
    STR_FIELD(audio_mixer),
    STR_FIELD(audio_jack_device_name),
    INT_FIELD(audio_mic),
    STR_FIELD(input_gamepad_device_name),
    STR_FIELD(input_power_device_name),
    STR_FIELD(input_volume_device_name),
    STR_FIELD(input_lid_device_name),
    STR_FIELD(input_rumble_device_name),
    INT_FIELD(input_touch),
    STR_FIELD(input_touch_device_name),
    INT_FIELD(key_up),
    INT_FIELD(key_down),
    INT_FIELD(key_left),
    INT_FIELD(key_right),
    INT_FIELD(key_a),
    INT_FIELD(key_b),
    INT_FIELD(key_c),
    INT_FIELD(key_x),
    INT_FIELD(key_y),
    INT_FIELD(key_z),
    INT_FIELD(key_l1),
    INT_FIELD(key_r1),
    INT_FIELD(key_l2),
    INT_FIELD(key_r2),
    INT_FIELD(key_l3),
    INT_FIELD(key_r3),
    INT_FIELD(key_start),
    INT_FIELD(key_select),
    INT_FIELD(key_menu),
    INT_FIELD(key_power),
    INT_FIELD(key_vol_up),
    INT_FIELD(key_vol_down),
    INT_FIELD(input_axis_lx),
    INT_FIELD(input_axis_ly),
    INT_FIELD(input_axis_rx),
    INT_FIELD(input_axis_ry),
    INT_FIELD(input_axis_min),
    INT_FIELD(input_axis_center),
    INT_FIELD(input_axis_max),
    INT_FIELD(input_axis_lx_invert),
    INT_FIELD(input_axis_ly_invert),
    INT_FIELD(input_axis_rx_invert),
    INT_FIELD(input_axis_ry_invert),
    STR_FIELD(wifi_interface),
    STR_FIELD(bluetooth_interface),
    STR_FIELD(power_battery_sysfs),
    STR_FIELD(power_charger_online_path),
    STR_FIELD(power_led_path),
    INT_FIELD(usb_otg),
    INT_FIELD(usb_host_ports),
    INT_FIELD(usb_device_mode),
    INT_FIELD(usb_controller_mode),
    STR_FIELD(storage_sd_node),
    STR_FIELD(storage_sd2_node),
    STR_FIELD(storage_emmc_node),
};

#define TRAIT_FIELD_COUNT (sizeof(TRAIT_FIELDS) / sizeof(TRAIT_FIELDS[0]))

static MinimeTraitsRef traits;
static int initialized;
static int valid;

static char *trim(char *text) {
    char *end;
    while (*text && isspace((unsigned char)*text))
        text++;
    end = text + strlen(text);
    while (end > text && isspace((unsigned char)end[-1]))
        end--;
    *end = '\0';
    return text;
}

static void copyText(char *dst, size_t size, const char *src) {
    if (!dst || !size)
        return;
    snprintf(dst, size, "%s", src ? src : "");
}

static int parseInt(const char *value) {
    char *end;
    long parsed;

    if (!value || !strcmp(value, NA))
        return -1;
    parsed = strtol(value, &end, 10);
    return *end ? -1 : (int)parsed;
}

static const TraitField *findField(const char *key) {
    for (size_t i = 0; i < TRAIT_FIELD_COUNT; i++) {
        if (!strcmp(key, TRAIT_FIELDS[i].key))
            return &TRAIT_FIELDS[i];
    }
    return NULL;
}

// Apply a single key=value line. Returns 0 on success, -1 on unknown key or
// malformed integer. `na` is allowed only for integer (nullable) fields and
// maps to -1; string fields that are absent or "na" stay empty.
static int setValue(const char *key, const char *value) {
    const TraitField *field = findField(key);
    if (!field) {
        fprintf(stderr, "Minime traits: unknown key '%s' in %s\n", key, MINIME_TRAITS_PATH);
        return -1;
    }

    if (field->type == TYPE_STRING) {
        copyText((char *)&traits + field->offset, MINIME_TRAIT_NAME_MAX, value);
        return 0;
    }

    if (field->type == TYPE_ASPECT) {
        // Value is "W:H" (e.g. "4:3"); maps to the aspect enum. Missing/na
        // stays UNKNOWN and the init derive step fills it from dimensions.
        MinimeScreenAspect aspect = MINIME_ASPECT_UNKNOWN;
        int w = 0, h = 0;
        if (sscanf(value, "%d:%d", &w, &h) == 2 && w > 0 && h > 0) {
            if (w * 3 == h * 4)
                aspect = MINIME_ASPECT_4x3;
            else if (w * 2 == h * 3)
                aspect = MINIME_ASPECT_3x2;
            else if (w * 9 == h * 16)
                aspect = MINIME_ASPECT_16x9;
            else if (w == h)
                aspect = MINIME_ASPECT_1x1;
        }
        *(MinimeScreenAspect *)((char *)&traits + field->offset) = aspect;
        return 0;
    }

    int parsed = parseInt(value);
    if (parsed < 0 && strcmp(value, NA)) {
        fprintf(stderr, "Minime traits: invalid integer '%s' for '%s'\n", value, key);
        return -1;
    }
    *(int *)((char *)&traits + field->offset) = parsed;
    return 0;
}

int MINIME_traitAvailable(const char *value) {
    return value && value[0] && strcmp(value, NA);
}

// Resolve the stable gpu_hdmi_connector (e.g. "HDMI-A-1") to the actual DRM
// sysfs status path. The card number prefix ("card0", "card1", ...) is the
// DRM primary-minor index, allocated first-come-first-serve at probe time,
// so it is NOT part of the trait file — we glob /sys/class/drm/card* and
// pick the connector whose suffix matches. Empty connector means no HDMI.
static void resolve_hdmi_connector(void) {
    const char *connector = traits.gpu_hdmi_connector;

    if (!MINIME_traitAvailable(connector))
        return;

    DIR *dir = opendir("/sys/class/drm");
    if (!dir)
        return;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        const char *name = entry->d_name;
        const char *dash = strchr(name, '-');
        if (!dash)
            continue;
        // name = "cardN-<connector>"; match the suffix after the card prefix.
        if (strcmp(dash + 1, connector) == 0) {
            snprintf(traits.gpu_hdmi_state_path, sizeof(traits.gpu_hdmi_state_path),
                     "/sys/class/drm/%s/status", name);
            break;
        }
    }
    closedir(dir);
}

static int validate(void) {
    if (!traits.device_id[0] || !traits.device_model[0] ||
        !MINIME_traitAvailable(traits.gpu_device) || traits.screen_width <= 0 ||
        traits.screen_height <= 0 || traits.screen_rotation < 0 ||
        !MINIME_traitAvailable(traits.screen_backlight_path) ||
        traits.screen_backlight_max <= 0 || !MINIME_traitAvailable(traits.input_gamepad_device_name) ||
        !MINIME_traitAvailable(traits.input_power_device_name) ||
        !MINIME_traitAvailable(traits.input_volume_device_name) ||
        traits.key_up < 0 || traits.key_down < 0 || traits.key_left < 0 ||
        traits.key_right < 0 || traits.key_a < 0 || traits.key_b < 0 ||
        traits.key_x < 0 || traits.key_y < 0 || traits.key_start < 0 ||
        traits.key_select < 0 || traits.key_menu < 0 || traits.key_power < 0 ||
        traits.key_vol_up < 0 || traits.key_vol_down < 0) {
        fprintf(stderr, "Invalid required Minime traits in %s\n", MINIME_TRAITS_PATH);
        return -1;
    }
    return 0;
}

int MINIME_traitsInit(void) {
    FILE *file;
    char line[512];

    if (initialized)
        return valid ? 0 : -1;
    initialized = 1;
    memset(&traits, 0, sizeof(traits));
    traits.key_c = traits.key_z = -1;
    traits.key_l1 = traits.key_r1 = -1;
    traits.key_l2 = traits.key_r2 = -1;
    traits.key_l3 = traits.key_r3 = -1;
    traits.input_axis_lx = traits.input_axis_ly = -1;
    traits.input_axis_rx = traits.input_axis_ry = -1;
    traits.input_axis_min = traits.input_axis_center = traits.input_axis_max = -1;

    file = fopen(MINIME_TRAITS_PATH, "r");
    if (!file) {
        fprintf(stderr, "Missing Minime traits: %s\n", MINIME_TRAITS_PATH);
        return -1;
    }
    while (fgets(line, sizeof(line), file)) {
        char *key;
        char *value;

        key = trim(line);
        if (!key[0] || key[0] == '#' || key[0] == '[')
            continue;
        value = strchr(key, '=');
        if (!value)
            continue;
        *value++ = '\0';
        if (setValue(trim(key), trim(value)) != 0) {
            fclose(file);
            return -1;
        }
    }
    fclose(file);

    // screen_aspect is parsed from the file when present; derive it from the
    // panel dimensions only as a fallback so the emitted value is authoritative.
    if (traits.screen_aspect == MINIME_ASPECT_UNKNOWN && traits.screen_width > 0 &&
        traits.screen_height > 0) {
        if (traits.screen_width * 3 == traits.screen_height * 4)
            traits.screen_aspect = MINIME_ASPECT_4x3;
        else if (traits.screen_width * 2 == traits.screen_height * 3)
            traits.screen_aspect = MINIME_ASPECT_3x2;
        else if (traits.screen_width * 9 == traits.screen_height * 16)
            traits.screen_aspect = MINIME_ASPECT_16x9;
        else if (traits.screen_width == traits.screen_height)
            traits.screen_aspect = MINIME_ASPECT_1x1;
    }

    resolve_hdmi_connector();

    valid = validate() == 0;
    return valid ? 0 : -1;
}

const MinimeTraitsRef *MINIME_traits(void) {
    return MINIME_traitsInit() == 0 ? &traits : NULL;
}

int MINIME_hasSecondScreen(void) {
    const MinimeTraitsRef *traits = MINIME_traits();

    return traits && traits->screen2_width > 0 && traits->screen2_height > 0;
}
