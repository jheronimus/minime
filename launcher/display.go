package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/unix"
)

// Display provides hardware-accelerated presentation to the screen.
type Display interface {
	Width() int
	Height() int
	Present(rgba []byte, srcWidth, srcHeight int) error
	Close() error
}

// NewDisplay initializes a native DRM/KMS display if on Linux, or returns nil on desktop.
func NewDisplay() (Display, error) {
	if runtime.GOOS != "linux" {
		return nil, nil
	}
	return initDRMDisplay()
}

// DRM and KMS ioctl definitions for Linux
const (
	drmIocNone  = 0
	drmIocWrite = 1
	drmIocRead  = 2

	drmIocDirShift  = 30
	drmIocTypeShift = 8
	drmIocNrShift   = 0
	drmIocSizeShift = 16

	drmType = 0x64 // 'd'
)

func drmIOC(dir, typ, nr, size uintptr) uintptr {
	return (dir << drmIocDirShift) | (typ << drmIocTypeShift) | (nr << drmIocNrShift) | (size << drmIocSizeShift)
}

func drmIOWR(typ, nr, size uintptr) uintptr {
	return drmIOC(drmIocRead|drmIocWrite, typ, nr, size)
}

func drmIO(typ, nr uintptr) uintptr {
	return drmIOC(drmIocNone, typ, nr, 0)
}

type drmModeCardRes struct {
	fbIDPtr         uint64
	crtcIDPtr       uint64
	connectorIDPtr  uint64
	encoderIDPtr    uint64
	countFBs        uint32
	countCRTCs      uint32
	countConnectors uint32
	countEncoders   uint32
	minWidth        uint32
	maxWidth        uint32
	minHeight       uint32
	maxHeight       uint32
}

type drmModeModeInfo struct {
	clock      uint32
	hdisplay   uint16
	hsyncStart uint16
	hsyncEnd   uint16
	htotal     uint16
	hskew      uint16
	vdisplay   uint16
	vsyncStart uint16
	vsyncEnd   uint16
	vtotal     uint16
	vscan      uint16
	vrefresh   uint32
	flags      uint32
	typ        uint32
	name       [32]byte
}

type drmModeGetConnector struct {
	encodersPtr     uint64
	modesPtr        uint64
	propsPtr        uint64
	propValuesPtr   uint64
	countModes      uint32
	countProps      uint32
	countEncoders   uint32
	encoderID       uint32
	connectorID     uint32
	connectorType   uint32
	connectorTypeID uint32
	connection      uint32
	mmWidth         uint32
	mmHeight        uint32
	subpixel        uint32
	pad             uint32
}

type drmModeGetEncoder struct {
	encoderID      uint32
	encoderType    uint32
	crtcID         uint32
	possibleCrtcs  uint32
	possibleClones uint32
}

type drmModeCreateDumb struct {
	height uint32
	width  uint32
	bpp    uint32
	flags  uint32
	handle uint32
	pitch  uint32
	size   uint64
}

type drmModeDestroyDumb struct {
	handle uint32
}

type drmModeMapDumb struct {
	handle uint32
	pad    uint32
	offset uint64
}

type drmModeFBCmd struct {
	fbID   uint32
	width  uint32
	height uint32
	pitch  uint32
	bpp    uint32
	depth  uint32
	handle uint32
}

type drmModeCrtc struct {
	setConnectorsPtr uint64
	countConnectors  uint32
	crtcID           uint32
	fbID             uint32
	x                uint32
	y                uint32
	gammaSize        uint32
	modeValid        uint32
	mode             drmModeModeInfo
}

type drmModeCrtcPageFlip struct {
	crtcID   uint32
	fbID     uint32
	flags    uint32
	reserved uint32
	userData uint64
}

var (
	drmIoctlSetMaster   = drmIO(drmType, 0x1e)
	drmIoctlDropMaster  = drmIO(drmType, 0x1f)
	drmIoctlGetRes      = drmIOWR(drmType, 0xA0, unsafe.Sizeof(drmModeCardRes{}))
	drmIoctlGetConn     = drmIOWR(drmType, 0xA7, unsafe.Sizeof(drmModeGetConnector{}))
	drmIoctlGetEnc      = drmIOWR(drmType, 0xA6, unsafe.Sizeof(drmModeGetEncoder{}))
	drmIoctlCreateDumb  = drmIOWR(drmType, 0xB2, unsafe.Sizeof(drmModeCreateDumb{}))
	drmIoctlDestroyDumb = drmIOWR(drmType, 0xB4, unsafe.Sizeof(drmModeDestroyDumb{}))
	drmIoctlMapDumb     = drmIOWR(drmType, 0xB3, unsafe.Sizeof(drmModeMapDumb{}))
	drmIoctlAddFB       = drmIOWR(drmType, 0xAE, unsafe.Sizeof(drmModeFBCmd{}))
	drmIoctlRmFB        = drmIOWR(drmType, 0xAF, unsafe.Sizeof(uint32(0)))
	drmIoctlSetCrtc     = drmIOWR(drmType, 0xA2, unsafe.Sizeof(drmModeCrtc{}))
	drmIoctlPageFlip    = drmIOWR(drmType, 0xB0, unsafe.Sizeof(drmModeCrtcPageFlip{}))
)

func drmCall(fd uintptr, req uintptr, arg unsafe.Pointer) error {
	_, _, err := syscall.Syscall(syscall.SYS_IOCTL, fd, req, uintptr(arg))
	if err != 0 {
		return err
	}
	return nil
}

type drmBuffer struct {
	handle uint32
	fbID   uint32
	size   uint64
	pitch  uint32
	data   []byte
}

type drmDisplay struct {
	file        *os.File
	connectorID uint32
	crtcID      uint32
	mode        drmModeModeInfo
	width       int
	height      int
	pitch       int

	bufs      [2]drmBuffer
	activeIdx int
	mu        sync.Mutex
	closed    bool
}

func initDRMDisplay() (Display, error) {
	// Signal bootsplash to release DRM master
	_ = os.WriteFile("/tmp/nextui_exec", []byte("1"), 0644)
	time.Sleep(100 * time.Millisecond)

	cards, err := filepath.Glob("/dev/dri/card*")
	if err != nil || len(cards) == 0 {
		return nil, fmt.Errorf("no /dev/dri/card* found")
	}

	var fd *os.File
	var res drmModeCardRes

	for _, card := range cards {
		f, err := os.OpenFile(card, os.O_RDWR, 0)
		if err != nil {
			continue
		}

		var r drmModeCardRes
		if err := drmCall(f.Fd(), drmIoctlGetRes, unsafe.Pointer(&r)); err == nil && r.countConnectors > 0 {
			_ = drmCall(f.Fd(), drmIoctlSetMaster, nil)
			fd = f
			res = r
			break
		}
		_ = f.Close()
	}

	if fd == nil {
		return nil, fmt.Errorf("no KMS-capable DRM card found")
	}

	fbs := make([]uint32, max(1, int(res.countFBs)))
	encs := make([]uint32, max(1, int(res.countEncoders)))
	conns := make([]uint32, max(1, int(res.countConnectors)))
	crtcs := make([]uint32, max(1, int(res.countCRTCs)))

	res.fbIDPtr = uint64(uintptr(unsafe.Pointer(&fbs[0])))
	res.encoderIDPtr = uint64(uintptr(unsafe.Pointer(&encs[0])))
	res.connectorIDPtr = uint64(uintptr(unsafe.Pointer(&conns[0])))
	res.crtcIDPtr = uint64(uintptr(unsafe.Pointer(&crtcs[0])))

	if err := drmCall(fd.Fd(), drmIoctlGetRes, unsafe.Pointer(&res)); err != nil {
		_ = fd.Close()
		return nil, fmt.Errorf("drm get resources: %w", err)
	}

	var connID uint32
	var crtcID uint32
	var selectedMode drmModeModeInfo
	found := false

	for _, cid := range conns[:res.countConnectors] {
		var conn drmModeGetConnector
		conn.connectorID = cid
		if err := drmCall(fd.Fd(), drmIoctlGetConn, unsafe.Pointer(&conn)); err != nil {
			continue
		}
		if conn.connection != 1 || conn.countModes == 0 {
			continue
		}

		modes := make([]drmModeModeInfo, conn.countModes)
		encIDs := make([]uint32, max(1, int(conn.countEncoders)))
		conn.modesPtr = uint64(uintptr(unsafe.Pointer(&modes[0])))
		conn.encodersPtr = uint64(uintptr(unsafe.Pointer(&encIDs[0])))
		conn.propsPtr = 0
		conn.propValuesPtr = 0
		conn.countProps = 0

		if err := drmCall(fd.Fd(), drmIoctlGetConn, unsafe.Pointer(&conn)); err != nil {
			continue
		}

		connID = cid
		selectedMode = modes[0]
		if conn.encoderID != 0 {
			var enc drmModeGetEncoder
			enc.encoderID = conn.encoderID
			if err := drmCall(fd.Fd(), drmIoctlGetEnc, unsafe.Pointer(&enc)); err == nil {
				crtcID = enc.crtcID
			}
		}
		if crtcID == 0 && len(crtcs) > 0 {
			crtcID = crtcs[0]
		}
		found = true
		break
	}

	if !found {
		_ = fd.Close()
		return nil, fmt.Errorf("no connected display connector found")
	}

	w := int(selectedMode.hdisplay)
	h := int(selectedMode.vdisplay)

	disp := &drmDisplay{
		file:        fd,
		connectorID: connID,
		crtcID:      crtcID,
		mode:        selectedMode,
		width:       w,
		height:      h,
	}

	// Allocate double-buffered dumb buffers
	for i := 0; i < 2; i++ {
		cd := drmModeCreateDumb{
			width:  uint32(w),
			height: uint32(h),
			bpp:    32,
		}
		if err := drmCall(fd.Fd(), drmIoctlCreateDumb, unsafe.Pointer(&cd)); err != nil {
			_ = disp.Close()
			return nil, fmt.Errorf("create dumb buffer %d: %w", i, err)
		}
		disp.pitch = int(cd.pitch)

		fbCmd := drmModeFBCmd{
			width:  cd.width,
			height: cd.height,
			pitch:  cd.pitch,
			bpp:    32,
			depth:  24,
			handle: cd.handle,
		}
		if err := drmCall(fd.Fd(), drmIoctlAddFB, unsafe.Pointer(&fbCmd)); err != nil {
			_ = disp.Close()
			return nil, fmt.Errorf("add fb %d: %w", i, err)
		}

		mapDumb := drmModeMapDumb{handle: cd.handle}
		if err := drmCall(fd.Fd(), drmIoctlMapDumb, unsafe.Pointer(&mapDumb)); err != nil {
			_ = disp.Close()
			return nil, fmt.Errorf("map dumb %d: %w", i, err)
		}

		data, err := unix.Mmap(int(fd.Fd()), int64(mapDumb.offset), int(cd.size), unix.PROT_READ|unix.PROT_WRITE, unix.MAP_SHARED)
		if err != nil {
			_ = disp.Close()
			return nil, fmt.Errorf("mmap buffer %d: %w", i, err)
		}

		disp.bufs[i] = drmBuffer{
			handle: cd.handle,
			fbID:   fbCmd.fbID,
			size:   cd.size,
			pitch:  cd.pitch,
			data:   data,
		}
	}

	// Initial CRTC modeset on buffer 0
	setConnID := connID
	crtc := drmModeCrtc{
		setConnectorsPtr: uint64(uintptr(unsafe.Pointer(&setConnID))),
		countConnectors:  1,
		crtcID:           crtcID,
		fbID:             disp.bufs[0].fbID,
		modeValid:        1,
		mode:             selectedMode,
	}
	if err := drmCall(fd.Fd(), drmIoctlSetCrtc, unsafe.Pointer(&crtc)); err != nil {
		_ = disp.Close()
		return nil, fmt.Errorf("set crtc: %w", err)
	}

	return disp, nil
}

func (d *drmDisplay) Width() int {
	return d.width
}

func (d *drmDisplay) Height() int {
	return d.height
}

func (d *drmDisplay) Present(rgba []byte, srcW, srcH int) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	if d.closed || srcW <= 0 || srcH <= 0 || len(rgba) < srcW*srcH*4 {
		return nil
	}

	// Render to next buffer
	nextIdx := 1 - d.activeIdx
	buf := &d.bufs[nextIdx]

	dstW := d.width
	dstH := d.height
	dstPitch := d.pitch

	// Aspect-fit scale calculation
	scaleX := dstW / srcW
	scaleY := dstH / srcH
	scale := scaleX
	if scaleY < scale {
		scale = scaleY
	}
	if scale < 1 {
		scale = 1
	}

	scaledW := srcW * scale
	scaledH := srcH * scale
	offsetX := (dstW - scaledW) / 2
	offsetY := (dstH - scaledH) / 2

	// Fast scaled copy into buffer
	for sy := 0; sy < srcH; sy++ {
		srcRow := rgba[sy*srcW*4 : (sy+1)*srcW*4]
		for dy := 0; dy < scale; dy++ {
			targetY := offsetY + sy*scale + dy
			if targetY < 0 || targetY >= dstH {
				continue
			}
			rowStart := targetY * dstPitch
			for sx := 0; sx < srcW; sx++ {
				sp := sx * 4
				r, g, b, a := srcRow[sp], srcRow[sp+1], srcRow[sp+2], srcRow[sp+3]
				for dx := 0; dx < scale; dx++ {
					targetX := offsetX + sx*scale + dx
					if targetX < 0 || targetX >= dstW {
						continue
					}
					dp := rowStart + targetX*4
					buf.data[dp] = b
					buf.data[dp+1] = g
					buf.data[dp+2] = r
					buf.data[dp+3] = a
				}
			}
		}
	}

	// Issue page flip
	flip := drmModeCrtcPageFlip{
		crtcID: d.crtcID,
		fbID:   buf.fbID,
	}

	// Retry briefly if previous flip is still pending (vblank sync)
	for retries := 0; retries < 10; retries++ {
		err := drmCall(d.file.Fd(), drmIoctlPageFlip, unsafe.Pointer(&flip))
		if err == nil {
			d.activeIdx = nextIdx
			return nil
		}
		if errorsIs(err, unix.EBUSY) {
			time.Sleep(1 * time.Millisecond)
			continue
		}
		// If page flip fails (e.g. crtc unblank), fallback to SetCrtc
		setConnID := d.connectorID
		crtc := drmModeCrtc{
			setConnectorsPtr: uint64(uintptr(unsafe.Pointer(&setConnID))),
			countConnectors:  1,
			crtcID:           d.crtcID,
			fbID:             buf.fbID,
			modeValid:        1,
			mode:             d.mode,
		}
		_ = drmCall(d.file.Fd(), drmIoctlSetCrtc, unsafe.Pointer(&crtc))
		d.activeIdx = nextIdx
		return nil
	}

	return nil
}

func (d *drmDisplay) Close() error {
	d.mu.Lock()
	defer d.mu.Unlock()

	if d.closed {
		return nil
	}
	d.closed = true

	for i := 0; i < 2; i++ {
		if len(d.bufs[i].data) > 0 {
			_ = unix.Munmap(d.bufs[i].data)
			d.bufs[i].data = nil
		}
		if d.bufs[i].fbID != 0 {
			_ = drmCall(d.file.Fd(), drmIoctlRmFB, unsafe.Pointer(&d.bufs[i].fbID))
		}
		if d.bufs[i].handle != 0 {
			dd := drmModeDestroyDumb{handle: d.bufs[i].handle}
			_ = drmCall(d.file.Fd(), drmIoctlDestroyDumb, unsafe.Pointer(&dd))
		}
	}

	if d.file != nil {
		_ = drmCall(d.file.Fd(), drmIoctlDropMaster, nil)
		_ = d.file.Close()
	}
	return nil
}
