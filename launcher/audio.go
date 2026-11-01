package main

import (
	"sync"
	"unsafe"
)

const defaultAudioCapacity = 16384 * 4

// audioBuffer provides a thread-safe circular ring buffer feeding Ebiten's audio player.
type audioBuffer struct {
	mutex sync.Mutex
	data  []byte
	head  int
	tail  int
	size  int
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

	for _, sample := range samples {
		lowByte := byte(sample)
		highByte := byte(sample >> 8)
		if buffer.size+2 > len(buffer.data) {
			// Drop oldest samples on overflow to prevent runaway latency
			buffer.head = (buffer.head + 2) % len(buffer.data)
			buffer.size -= 2
		}
		buffer.data[buffer.tail] = lowByte
		buffer.data[(buffer.tail+1)%len(buffer.data)] = highByte
		buffer.tail = (buffer.tail + 2) % len(buffer.data)
		buffer.size += 2
	}

	return frames
}

// Read implements io.Reader, supplying PCM bytes to the Ebiten audio player.
func (buffer *audioBuffer) Read(destination []byte) (int, error) {
	buffer.mutex.Lock()
	defer buffer.mutex.Unlock()

	if buffer.size == 0 {
		for i := range destination {
			destination[i] = 0
		}
		return len(destination), nil
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

	for i := bytesToRead; i < len(destination); i++ {
		destination[i] = 0
	}
	return len(destination), nil
}
