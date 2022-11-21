package sniff

import "bytes"

type Sniffer interface {
	Sniff(header []byte) bool
}

var audioExtensions = map[string]Sniffer{
	// ref: https://mimesniff.spec.whatwg.org
	".mp3": prefixSniffer("ID3"),
	".ogg": prefixSniffer("OggS"),
	".wav": prefixSniffer("RIFF"),

	// ref: https://www.loc.gov/preservation/digital/formats/fdd/fdd000027.shtml
	".wma": prefixSniffer{
		0x30, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11,
		0xa6, 0xd9, 0x00, 0xaa, 0x00, 0x62, 0xce, 0x6c,
	},

	// ref: https://www.garykessler.net/library/file_sigs.html
	".m4a": mpeg4Sniffer{},            // MPEG-4 container, m4a treat as audio
	".aac": prefixSniffer{0xFF, 0xF1}, // MPEG-4 AAC-LC

	".flac": prefixSniffer("fLaC"), // ref: https://xiph.org/flac/format.html
	".dff":  prefixSniffer("FRM8"), // DSDIFF, ref: https://www.sonicstudio.com/pdf/dsd/DSDIFF_1.5_Spec.pdf

}

// AudioExtension sniffs the known audio types, and returns the file extension.
// header is recommended to at least 16 bytes.
func AudioExtension(header []byte) (string, bool) {
	for ext, sniffer := range audioExtensions {
		if sniffer.Sniff(header) {
			return ext, true
		}
	}
	return "", false
}

// AudioExtensionWithFallback is equivalent to AudioExtension, but returns fallback
// most likely to use .mp3 as fallback, because mp3 files may not have ID3v2 tag.
func AudioExtensionWithFallback(header []byte, fallback string) string {
	ext, ok := AudioExtension(header)
	if !ok {
		return fallback
	}
	return ext
}

type prefixSniffer []byte

func (s prefixSniffer) Sniff(header []byte) bool {
	return bytes.HasPrefix(header, s)
}

type mpeg4Sniffer struct{}

func (mpeg4Sniffer) Sniff(header []byte) bool {
	return len(header) >= 8 && bytes.Equal([]byte("ftyp"), header[4:8])
}
