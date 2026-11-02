package main

import (
	"sync"
)

const (
	outputSampleRate = 48000
	// 80ms capacity buffer at 48kHz stereo 16-bit (48000 * 4 * 0.080 ≈ 15360 bytes).
	audioBufferCapacity = 16384
	// Target watermark is 50% capacity (~40ms latency).
	targetWatermark = audioBufferCapacity / 2
)

// AudioBuffer provides a thread-safe ring buffer feeding the audio output
// with 4-point Cubic Hermite resampling and Dynamic Rate Control (DRC).
type AudioBuffer struct {
	mutex sync.Mutex
	data  []byte
	head  int
	tail  int
	size  int

	rateIn  int
	rateOut int

	// Cubic Hermite history (4 samples for Left and Right channels).
	histL [4]float64
	histR [4]float64
	phase float64
}

// NewAudioBuffer initializes an audio ring buffer configured for outputSampleRate.
func NewAudioBuffer() *AudioBuffer {
	return &AudioBuffer{
		data:    make([]byte, audioBufferCapacity),
		rateOut: outputSampleRate,
	}
}

// SetRates configures input (core) and output sample rates.
func (ab *AudioBuffer) SetRates(rateIn, rateOut int) {
	ab.mutex.Lock()
	defer ab.mutex.Unlock()

	ab.rateIn = rateIn
	ab.rateOut = rateOut
	ab.phase = 0
	ab.histL = [4]float64{}
	ab.histR = [4]float64{}
}

// WriteSamples receives interleaved stereo 16-bit PCM from the emulation core,
// resamples to outputSampleRate with Dynamic Rate Control, and pushes to the ring buffer.
func (ab *AudioBuffer) WriteSamples(samples []int16) {
	frames := len(samples) / 2
	if frames == 0 {
		return
	}

	ab.mutex.Lock()
	defer ab.mutex.Unlock()

	// Direct pass-through if rates match or rates are unconfigured
	if ab.rateIn <= 0 || ab.rateOut <= 0 || ab.rateIn == ab.rateOut {
		for f := 0; f < frames; f++ {
			ab.pushFrame(samples[f*2], samples[f*2+1])
		}
		return
	}

	// Dynamic Rate Control (DRC):
	// Modulate input consumption step by ±0.75% based on buffer fullness relative to target watermark.
	// If buffer is filling up (>50%), consume input slightly faster (advance phase faster).
	// If buffer is draining (<50%), consume input slightly slower.
	fillDiff := float64(ab.size-targetWatermark) / float64(targetWatermark)
	if fillDiff > 1.0 {
		fillDiff = 1.0
	} else if fillDiff < -1.0 {
		fillDiff = -1.0
	}
	drcFactor := 1.0 + 0.0075*fillDiff
	step := (float64(ab.rateIn) / float64(ab.rateOut)) * drcFactor

	for f := 0; f < frames; f++ {
		newL := float64(samples[f*2])
		newR := float64(samples[f*2+1])

		// Shift 4-point history window: p0, p1, p2, p3
		ab.histL[0], ab.histL[1], ab.histL[2], ab.histL[3] = ab.histL[1], ab.histL[2], ab.histL[3], newL
		ab.histR[0], ab.histR[1], ab.histR[2], ab.histR[3] = ab.histR[1], ab.histR[2], ab.histR[3], newR

		// Interpolate and produce output samples while phase < 1.0
		for ab.phase < 1.0 {
			outL := hermiteInterpolation(ab.histL[0], ab.histL[1], ab.histL[2], ab.histL[3], ab.phase)
			outR := hermiteInterpolation(ab.histR[0], ab.histR[1], ab.histR[2], ab.histR[3], ab.phase)

			ab.pushFrame(clampInt16(outL), clampInt16(outR))
			ab.phase += step
		}

		ab.phase -= 1.0
	}
}

// pushFrame appends a single 16-bit stereo frame (4 bytes) to the circular buffer.
// If the buffer is full, it drops the oldest frame to preserve bounded audio latency.
func (ab *AudioBuffer) pushFrame(left, right int16) {
	if ab.size+4 > len(ab.data) {
		ab.head = (ab.head + 4) % len(ab.data)
		ab.size -= 4
	}

	ab.data[ab.tail] = byte(left)
	ab.data[(ab.tail+1)%len(ab.data)] = byte(left >> 8)
	ab.data[(ab.tail+2)%len(ab.data)] = byte(right)
	ab.data[(ab.tail+3)%len(ab.data)] = byte(right >> 8)

	ab.tail = (ab.tail + 4) % len(ab.data)
	ab.size += 4
}

// Read implements io.Reader, supplying PCM bytes to the audio device player.
func (ab *AudioBuffer) Read(dest []byte) (int, error) {
	ab.mutex.Lock()
	defer ab.mutex.Unlock()

	if ab.size == 0 {
		return 0, nil
	}

	toRead := len(dest)
	if toRead > ab.size {
		toRead = ab.size
	}

	for i := 0; i < toRead; i++ {
		dest[i] = ab.data[ab.head]
		ab.head = (ab.head + 1) % len(ab.data)
	}
	ab.size -= toRead

	return toRead, nil
}

// hermiteInterpolation computes 4-point cubic Hermite interpolation.
// t is the fractional phase in [0, 1).
func hermiteInterpolation(p0, p1, p2, p3, t float64) float64 {
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
