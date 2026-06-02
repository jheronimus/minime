#!/usr/bin/env python3
import os
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: patch_mali_dma_heap.py <sdl2_build_dir>")
        sys.exit(1)

    build_dir = sys.argv[1]
    header_path = os.path.join(build_dir, "src/video/mali-fbdev/SDL_malivideo.h")
    source_path = os.path.join(build_dir, "src/video/mali-fbdev/SDL_malivideo.c")
    mali_h_path = os.path.join(build_dir, "src/video/mali-fbdev/mali.h")

    if not os.path.exists(header_path) or not os.path.exists(source_path):
        print("Mali FBDEV source files not found. Patch might not have been applied yet.")
        sys.exit(1)

    # 0. Patch mali.h (32-bit types for alignment)
    if os.path.exists(mali_h_path):
        print(f"Skipping patching {mali_h_path} to keep unsigned long (64-bit)")

    # 1. Patch SDL_malivideo.h
    print(f"Patching {header_path}...")
    with open(header_path, "r") as f:
        header_content = f.read()

    header_target = "    int ion_fd;\n    struct MALI_Blitter *blitter;"
    header_replacement = "    int ion_fd;\n    int use_dma_heap;\n    struct MALI_Blitter *blitter;"

    if header_target in header_content:
        header_content = header_content.replace(header_target, header_replacement)
        with open(header_path, "w") as f:
            f.write(header_content)
        print("Successfully patched SDL_malivideo.h")
    else:
        print("Warning: Target not found in SDL_malivideo.h, maybe already patched?")

    # 2. Patch SDL_malivideo.c
    print(f"Patching {source_path}...")
    with open(source_path, "r") as f:
        source_content = f.read()

    # 2.1 Initialization
    init_target = """    data->ion_fd = open("/dev/ion", O_RDWR, 0);
    if (data->ion_fd < 0) {
        return SDL_SetError("mali-fbdev: Could not open ion device");
    }"""

    init_replacement = """    data->ion_fd = open("/dev/ion", O_RDWR, 0);
    data->use_dma_heap = 0;
    if (data->ion_fd < 0) {
        data->ion_fd = open("/dev/dma_heap/system", O_RDWR, 0);
        if (data->ion_fd < 0) {
            data->ion_fd = open("/dev/dma_heap/default_cma_region", O_RDWR, 0);
        }
        if (data->ion_fd < 0) {
            return SDL_SetError("mali-fbdev: Could not open /dev/ion or any /dev/dma_heap/*");
        }
        data->use_dma_heap = 1;
    }
    {
        mali_pixmap dummy;
        printf("=== MALI_PIXMAP STRUCT DIAGNOSTICS ===\\n");
        printf("sizeof(mali_plane) = %d\\n", (int)sizeof(mali_plane));
        printf("sizeof(mali_pixmap) = %d\\n", (int)sizeof(mali_pixmap));
        printf("offsetof(width) = %d\\n", (int)((char*)&dummy.width - (char*)&dummy));
        printf("offsetof(planes) = %d\\n", (int)((char*)&dummy.planes - (char*)&dummy));
        printf("offsetof(format) = %d\\n", (int)((char*)&dummy.format - (char*)&dummy));
        printf("offsetof(handles) = %d\\n", (int)((char*)&dummy.handles - (char*)&dummy));
        printf("offsetof(drm_fourcc) = %d\\n", (int)((char*)&dummy.drm_fourcc - (char*)&dummy));
        printf("======================================\\n");
        fflush(stdout);
    }"""

    if init_target in source_content:
        source_content = source_content.replace(init_target, init_replacement)
        print("Patched initialization logic in SDL_malivideo.c")
    else:
        print("Warning: Initialization target not found in SDL_malivideo.c")

    # 2.2 Allocation
    alloc_target = """        /* Allocate framebuffer data */
        allocation_data = (struct ion_allocation_data){
            .len = surf->pixmap.planes[0].size,
            .heap_id_mask = (1 << ION_HEAP_TYPE_DMA),
            .flags = 1 << ION_FLAG_CACHED
        };

        io = ioctl(displaydata->ion_fd, ION_IOC_ALLOC, &allocation_data);
        if (io != 0) {
            SDL_SetError("mali-fbdev: Unable to create backing ION buffers");
            return EGL_NO_SURFACE;
        }

        /* Export DMA_BUF handle for the framebuffer */
        ion_data = (struct ion_fd_data){
            .handle = allocation_data.handle
        };

        io = ioctl(displaydata->ion_fd, ION_IOC_SHARE, &ion_data);
        if (io != 0) {
            SDL_SetError("mali-fbdev: Failure exporting ION buffer handle");
            return EGL_NO_SURFACE;
        }

        /* Recall fd and handle for teardown later */
        surf->dmabuf_handle = allocation_data.handle;
        surf->dmabuf_fd = ion_data.fd;"""

    alloc_replacement = """        /* Allocate framebuffer data */
        if (displaydata->use_dma_heap) {
            struct dma_heap_allocation_data {
                __u64 len;
                __u32 fd;
                __u32 fd_flags;
                __u64 heap_flags;
            };
            #define DMA_HEAP_IOC_MAGIC 'H'
            #define DMA_HEAP_IOCTL_ALLOC _IOWR(DMA_HEAP_IOC_MAGIC, 0x0, struct dma_heap_allocation_data)

            struct dma_heap_allocation_data dma_alloc = {
                .len = surf->pixmap.planes[0].size,
                .fd_flags = O_CLOEXEC | O_RDWR,
                .heap_flags = 0
            };
            printf("Allocating dma_heap buffer of size %llu\\n", (unsigned long long)dma_alloc.len);
            fflush(stdout);
            io = ioctl(displaydata->ion_fd, DMA_HEAP_IOCTL_ALLOC, &dma_alloc);
            printf("After dma_heap allocation ioctl: io = %d, fd = %d\\n", io, dma_alloc.fd);
            fflush(stdout);
            if (io != 0) {
                SDL_SetError("mali-fbdev: Unable to create backing dma_heap buffers");
                return EGL_NO_SURFACE;
            }
            surf->dmabuf_handle = 0;
            surf->dmabuf_fd = dma_alloc.fd;
        } else {
            allocation_data = (struct ion_allocation_data){
                .len = surf->pixmap.planes[0].size,
                .heap_id_mask = (1 << ION_HEAP_TYPE_DMA),
                .flags = 1 << ION_FLAG_CACHED
            };

            io = ioctl(displaydata->ion_fd, ION_IOC_ALLOC, &allocation_data);
            if (io != 0) {
                SDL_SetError("mali-fbdev: Unable to create backing ION buffers");
                return EGL_NO_SURFACE;
            }

            /* Export DMA_BUF handle for the framebuffer */
            ion_data = (struct ion_fd_data){
                .handle = allocation_data.handle
            };

            io = ioctl(displaydata->ion_fd, ION_IOC_SHARE, &ion_data);
            if (io != 0) {
                SDL_SetError("mali-fbdev: Failure exporting ION buffer handle");
                return EGL_NO_SURFACE;
            }

            /* Recall fd and handle for teardown later */
            surf->dmabuf_handle = allocation_data.handle;
            surf->dmabuf_fd = ion_data.fd;
        }"""

    if alloc_target in source_content:
        source_content = source_content.replace(alloc_target, alloc_replacement)
        print("Patched allocation logic in SDL_malivideo.c")
    else:
        print("Warning: Allocation target not found in SDL_malivideo.c")

    handle_target = "surf->pixmap.handles[0] = ion_data.fd;"
    handle_replacement = """surf->pixmap.handles[0] = surf->dmabuf_fd;
        printf("=== MALI_PIXMAP VALUE DIAGNOSTICS ===\\n");
        printf("width: %d, height: %d\\n", surf->pixmap.width, surf->pixmap.height);
        printf("planes[0].stride: %u, size: %u, offset: %u\\n", (unsigned int)surf->pixmap.planes[0].stride, (unsigned int)surf->pixmap.planes[0].size, (unsigned int)surf->pixmap.planes[0].offset);
        printf("format: %llu\\n", (unsigned long long)surf->pixmap.format);
        printf("handles[0]: %d, [1]: %d, [2]: %d\\n", surf->pixmap.handles[0], surf->pixmap.handles[1], surf->pixmap.handles[2]);
        printf("drm_fourcc.format: 0x%x, modifier: %llu, dataspace: 0x%x\\n", surf->pixmap.drm_fourcc.format, (unsigned long long)surf->pixmap.drm_fourcc.modifier, surf->pixmap.drm_fourcc.dataspace);
        printf("=====================================\\n");
        fflush(stdout);"""
    if handle_target in source_content:
        source_content = source_content.replace(handle_target, handle_replacement)
        print("Patched handles[0] assignment in SDL_malivideo.c with value logging")
    else:
        print("Warning: handles[0] target not found in SDL_malivideo.c")

    # 2.3 Deallocation
    free_target = """        handle_data = (struct ion_handle_data){
            .handle = data->surface[i].dmabuf_handle
        };

        ioctl(displaydata->ion_fd, ION_IOC_FREE, &handle_data);
        data->surface[i].dmabuf_fd = -1;"""

    free_replacement = """        if (!displaydata->use_dma_heap) {
            handle_data = (struct ion_handle_data){
                .handle = data->surface[i].dmabuf_handle
            };

            ioctl(displaydata->ion_fd, ION_IOC_FREE, &handle_data);
        }
        data->surface[i].dmabuf_fd = -1;"""

    if free_target in source_content:
        source_content = source_content.replace(free_target, free_replacement)
        print("Patched deallocation logic in SDL_malivideo.c")
    else:
        print("Warning: Deallocation target not found in SDL_malivideo.c")

    create_target = """int
MALI_CreateWindow(_THIS, SDL_Window * window)
{
    SDL_WindowData *windowdata;
    SDL_VideoDisplay *display = SDL_GetDisplayForWindow(window);
    SDL_DisplayData *displaydata;
    EGLContext egl_context;

    displaydata = SDL_GetDisplayDriverData(0);"""
    
    create_replacement = """int
MALI_CreateWindow(_THIS, SDL_Window * window)
{
    SDL_WindowData *windowdata;
    SDL_VideoDisplay *display = SDL_GetDisplayForWindow(window);
    SDL_DisplayData *displaydata;
    EGLContext egl_context;

    displaydata = SDL_GetDisplayDriverData(0);
    printf("=== MALI_CREATEWINDOW DIAGNOSTICS ===\\n");
    printf("displaydata: %p\\n", displaydata);
    if (displaydata) {
        printf("displaydata->blitter: %p\\n", displaydata->blitter);
    }
    printf("======================================\\n");
    fflush(stdout);"""

    if create_target in source_content:
        source_content = source_content.replace(create_target, create_replacement)
        print("Patched MALI_CreateWindow in SDL_malivideo.c")
    else:
        print("Warning: MALI_CreateWindow target not found in SDL_malivideo.c")

    proc_target = """    if (displaydata->blitter) {
        displaydata->egl_create_pixmap_ID_mapping = SDL_EGL_GetProcAddress(_this, "egl_create_pixmap_ID_mapping");
        displaydata->egl_destroy_pixmap_ID_mapping = SDL_EGL_GetProcAddress(_this, "egl_destroy_pixmap_ID_mapping");"""

    proc_replacement = """    if (displaydata->blitter) {
        printf("Before SDL_EGL_GetProcAddress egl_create_pixmap_ID_mapping\\n");
        fflush(stdout);
        displaydata->egl_create_pixmap_ID_mapping = SDL_EGL_GetProcAddress(_this, "egl_create_pixmap_ID_mapping");
        if (!displaydata->egl_create_pixmap_ID_mapping) {
            printf("eglGetProcAddress returned NULL, falling back to SDL_LoadFunction\\n");
            fflush(stdout);
            void *egl_lib = SDL_LoadObject("libEGL.so.1");
            if (egl_lib) {
                displaydata->egl_create_pixmap_ID_mapping = SDL_LoadFunction(egl_lib, "egl_create_pixmap_ID_mapping");
            }
        }
        printf("After SDL_EGL_GetProcAddress: %p\\n", displaydata->egl_create_pixmap_ID_mapping);
        fflush(stdout);
        displaydata->egl_destroy_pixmap_ID_mapping = SDL_EGL_GetProcAddress(_this, "egl_destroy_pixmap_ID_mapping");
        if (!displaydata->egl_destroy_pixmap_ID_mapping) {
            void *egl_lib = SDL_LoadObject("libEGL.so.1");
            if (egl_lib) {
                displaydata->egl_destroy_pixmap_ID_mapping = SDL_LoadFunction(egl_lib, "egl_destroy_pixmap_ID_mapping");
            }
        }
        printf("After SDL_EGL_GetProcAddress egl_destroy_pixmap_ID_mapping: %p\\n", displaydata->egl_destroy_pixmap_ID_mapping);
        fflush(stdout);"""

    if proc_target in source_content:
        source_content = source_content.replace(proc_target, proc_replacement)
        print("Patched ProcAddress diagnostics in SDL_malivideo.c")
    else:
        print("Warning: ProcAddress target not found in SDL_malivideo.c")

    config_target = """    if (SDL_EGL_ChooseConfig(_this) != 0) {
        SDL_SetError("mali-fbdev: Unable to find a suitable EGL config");
        return EGL_NO_SURFACE;
    }"""

    config_replacement = """    printf("=== MALI_EGL_INITPIXMAPSURFACES START ===\\n");
    printf("Before SDL_EGL_ChooseConfig\\n");
    fflush(stdout);
    if (SDL_EGL_ChooseConfig(_this) != 0) {
        printf("SDL_EGL_ChooseConfig failed\\n");
        fflush(stdout);
        SDL_SetError("mali-fbdev: Unable to find a suitable EGL config");
        return EGL_NO_SURFACE;
    }
    printf("After SDL_EGL_ChooseConfig\\n");
    fflush(stdout);"""

    if config_target in source_content:
        source_content = source_content.replace(config_target, config_replacement)
        print("Patched ChooseConfig in SDL_malivideo.c with diagnostics")
    else:
        print("Warning: ChooseConfig target not found in SDL_malivideo.c")

    mapping_target = "surf->pixmap_handle = displaydata->egl_create_pixmap_ID_mapping(&surf->pixmap);"
    mapping_replacement = """printf("Before calling egl_create_pixmap_ID_mapping\\n");
        fflush(stdout);
        surf->pixmap_handle = displaydata->egl_create_pixmap_ID_mapping(&surf->pixmap);
        printf("After egl_create_pixmap_ID_mapping: handle = %p\\n", (void *)surf->pixmap_handle);
        fflush(stdout);"""

    if mapping_target in source_content:
        source_content = source_content.replace(mapping_target, mapping_replacement)
        print("Patched egl_create_pixmap_ID_mapping in SDL_malivideo.c with diagnostics")
    else:
        print("Warning: egl_create_pixmap_ID_mapping target not found in SDL_malivideo.c")

    # Save changes to SDL_malivideo.c
    with open(source_path, "w") as f:
        f.write(source_content)
    print("Successfully patched SDL_malivideo.c")

if __name__ == "__main__":
    main()
