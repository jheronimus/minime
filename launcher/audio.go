package main

import (
	"sync"
	"time"
	"unsafe"
)

const (
	outputSampleRate = 48000
	// 80ms capacity buffer at 48kHz stereo 16-bit (48000 * 4 * 0.080 ≈ 15360 bytes)
	audioBufferCapacity = 16384
	// Target watermark is 50% capacity (~40ms latency)
	targetWatermark = audioBufferCapacity / 2
)

// audioBuffer provides a thread-safe circular ring buffer feeding the audio player
// with Cubic Hermite resampling and Dynamic Rate Control (DRC).
type audioBuffer struct {
	mutex sync.Mutex
	data  []byte
	head  int
	tail  int
	size  int

	rateIn  int
	rateOut int

	// Cubic Hermite history (4 samples for L and R)
	histL [4]float64
	histR [4]float64
	phase float64
}

// SetRates configures the input (core) and output sample rates.
func (buffer *audioBuffer) SetRates(rateIn, rateOut int) {
	buffer.mutex.Lock()
	defer buffer.mutex.Unlock()
	buffer.rateIn = rateIn
	buffer.rateOut = rateOut
	buffer.phase = 0
	buffer.histL = [4]float64{}
	buffer.histR = [4]float64{}
}

func (buffer *audioBuffer) writeFrame(left, right int16) {
	if buffer.size+4 > len(buffer.data) {
		buffer.head = (buffer.head + 4) % len(buffer.data)
		buffer.size -= 4
	}

	lowL := byte(left)
	highL := byte(left >> 8)
	lowR := byte(right)
	highR := byte(right >> 8)

	buffer.data[buffer.tail] = lowL
	buffer.data[(buffer.tail+1)%len(buffer.data)] = highL
	buffer.data[(buffer.tail+2)%len(buffer.data)] = lowR
	buffer.data[(buffer.tail+3)%len(buffer.data)] = highR
	buffer.tail = (buffer.tail + 4) % len(buffer.data)
	buffer.size += 4
}

// hermite calculates 4-point cubic Hermite interpolation.
// t is the fractional phase in [0, 1).
func hermite(p0, p1, p2, p3, t float64) float64 {
	c0 := p1
	c1 := 0.5 * (p2 - p0)
	c2 := p0 - 2.5*p1 + 2.0*p2 - 0.5*p3
	c3 := 0.5*(p3-p0) + 1.5*(p1-p2)
	return ((c3*t+c2)*t+c1)*t + c0
}

func clampInt16(v float64) int16 {
	if v > 32767.0 {
		return 32767
	}
	if v < -32768.0 {
		return -32768
	}
	return int16(v)
}

// refreshAudio is the libretro audio_sample_batch callback.
// Cores stream blocks of interleaved 16-bit stereo PCM during retro_run().
func refreshAudio(data unsafe.Pointer, frames uintptr) uintptr {
	if activeCore == nil || data == nil || frames == 0 {
		return 0
	}

	samples := unsafe.Slice((*int16)(data), int(frames)*2)
	buffer := activeCore.audioBuf

	buffer.mutex.Lock()
	defer buffer.mutex.Unlock()

	// If buffer is critically full, yield briefly to backpressure emulation against DAC
	for tries := 0; tries < 5 && buffer.size+int(frames)*4 > len(buffer.data); tries++ {
		buffer.mutex.Unlock()
		time.Sleep(1 * time.Millisecond)
		buffer.mutex.Lock()
	}

	if buffer.rateIn <= 0 || buffer.rateOut <= 0 || buffer.rateIn == buffer.rateOut {
		for f := 0; f < int(frames); f++ {
			buffer.writeFrame(samples[f*2], samples[f*2+1])
		}
		return frames
	}

	// Dynamic Rate Control (DRC):
	// Modulate input consumption step by ±0.75% based on buffer fullness relative to target watermark.
	// If buffer is filling up (>50%), consume input slightly faster (advance phase faster).
	// If buffer is draining (<50%), consume input slightly slower.
	fillDiff := float64(buffer.size-targetWatermark) / float64(targetWatermark)
	if fillDiff > 1.0 {
		fillDiff = 1.0
	} else if fillDiff < -1.0 {
		fillDiff = -1.0
	}
	drcFactor := 1.0 + 0.0075*fillDiff

	step := (float64(buffer.rateIn) / float64(buffer.rateOut)) * drcFactor

	for f := 0; f < int(frames); f++ {
		newL := float64(samples[f*2])
		newR := float64(samples[f*2+1])

		// Shift history window: p0, p1, p2, p3
		buffer.histL[0], buffer.histL[1], buffer.histL[2], buffer.histL[3] = buffer.histL[1], buffer.histL[2], buffer.histL[3], newL
		buffer.histR[0], buffer.histR[1], buffer.histR[2], buffer.histR[3] = buffer.histR[1], buffer.histR[2], buffer.histR[3], newR

		// Produce output samples while phase < 1.0
		for buffer.phase < 1.0 {
			outL := hermite(buffer.histL[0], buffer.histL[1], buffer.histL[2], buffer.histL[3], buffer.phase)
			outR := hermite(buffer.histR[0], buffer.histR[1], buffer.histR[2], buffer.histR[3], buffer.phase)

			buffer.writeFrame(clampInt16(outL), clampInt16(outR))
			buffer.phase += step
		}

		buffer.phase -= 1.0
	}

	return frames
}

// Read implements io.Reader, supplying PCM bytes to the audio player.
func (buffer *audioBuffer) Read(destination []byte) (int, error) {
	buffer.mutex.Lock()
	defer buffer.mutex.Unlock()

	if buffer.size == 0 {
		return 0, nil
	}

	bytesToRead := len(destination)
	if bytesToRead > buffer.size {
		bytesToRead = buffer.size
	}
	for i := 0; i < bytesToRead; i++ {
		destination[i] = buffer.data[buffer.head]
		buffer.head = (buffer.head + 1) % len(buffer.data)
	}
	buffer.size -= bytesToRead

	return bytesToRead, nil
}
