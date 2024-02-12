package qmc

import (
	"encoding/binary"
	"fmt"
	"io"
)

type qqMusicTagMusicEx struct {
	songid        uint32 // Song ID
	unknown_1     uint32 // unused & unknown
	unknown_2     uint32 // unused & unknown
	mid           string // Media ID
	mediafile     string // real file name
	unknown_3     uint32 // unused; uninitialized memory?
	sizeof_struct uint32 // 19.57: fixed value: 0xC0
	version       uint32 // 19.57: fixed value: 0x01
	tag_magic     []byte // fixed value "musicex\0" (8 bytes)
}

func (tag *qqMusicTagMusicEx) Read(raw io.ReadSeeker) (int64, error) {
	_, err := raw.Seek(-16, io.SeekEnd)
	if err != nil {
		return 0, fmt.Errorf("musicex seek error: %w", err)
	}

	footerBuf := make([]byte, 4)
	footerBuf, err = io.ReadAll(io.LimitReader(raw, 4))
	if err != nil {
		return 0, fmt.Errorf("get musicex error: %w", err)
	}
	footerLen := int64(binary.LittleEndian.Uint32(footerBuf))

	audioLen, err := raw.Seek(-footerLen, io.SeekEnd)
	buf, err := io.ReadAll(io.LimitReader(raw, audioLen))
	if err != nil {
		return 0, err
	}

	tag.songid = binary.LittleEndian.Uint32(buf[0:4])
	tag.unknown_1 = binary.LittleEndian.Uint32(buf[4:8])
	tag.unknown_2 = binary.LittleEndian.Uint32(buf[8:12])

	for i := 0; i < 30; i++ {
		u := binary.LittleEndian.Uint16(buf[12+i*2 : 12+(i+1)*2])
		if u != 0 {
			tag.mid += string(u)
		}
	}
	for i := 0; i < 50; i++ {
		u := binary.LittleEndian.Uint16(buf[72+i*2 : 72+(i+1)*2])
		if u != 0 {
			tag.mediafile += string(u)
		}
	}

	tag.unknown_3 = binary.LittleEndian.Uint32(buf[173:177])
	tag.sizeof_struct = binary.LittleEndian.Uint32(buf[177:181])
	tag.version = binary.LittleEndian.Uint32(buf[181:185])
	tag.tag_magic = buf[185:193]

	return audioLen, nil
}
