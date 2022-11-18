package ncm

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/unlock-music/cli/algo/common"
	"github.com/unlock-music/cli/internal/utils"
)

var (
	magicHeader = []byte{
		0x43, 0x54, 0x45, 0x4E, 0x46, 0x44, 0x41, 0x4D}
	keyCore = []byte{
		0x68, 0x7a, 0x48, 0x52, 0x41, 0x6d, 0x73, 0x6f,
		0x35, 0x6b, 0x49, 0x6e, 0x62, 0x61, 0x78, 0x57}
	keyMeta = []byte{
		0x23, 0x31, 0x34, 0x6C, 0x6A, 0x6B, 0x5F, 0x21,
		0x5C, 0x5D, 0x26, 0x30, 0x55, 0x3C, 0x27, 0x28}
)

func NewDecoder(data []byte) common.Decoder {
	return &Decoder{
		file:    data,
		fileLen: uint32(len(data)),
	}
}

type Decoder struct {
	file    []byte
	fileLen uint32

	key []byte
	box []byte

	metaRaw  []byte
	metaType string
	meta     RawMeta

	cover []byte
	audio []byte

	offsetKey   uint32
	offsetMeta  uint32
	offsetCover uint32
	offsetAudio uint32
}

func (d *Decoder) Validate() error {
	if !bytes.Equal(magicHeader, d.file[:len(magicHeader)]) {
		return errors.New("ncm magic header not match")
	}
	d.offsetKey = 8 + 2
	return nil
}

func (d *Decoder) readKeyData() error {
	if d.offsetKey == 0 || d.offsetKey+4 > d.fileLen {
		return errors.New("invalid cover file offset")
	}
	bKeyLen := d.file[d.offsetKey : d.offsetKey+4]
	iKeyLen := binary.LittleEndian.Uint32(bKeyLen)
	d.offsetMeta = d.offsetKey + 4 + iKeyLen

	bKeyRaw := make([]byte, iKeyLen)
	for i := uint32(0); i < iKeyLen; i++ {
		bKeyRaw[i] = d.file[i+4+d.offsetKey] ^ 0x64
	}

	d.key = utils.PKCS7UnPadding(utils.DecryptAes128Ecb(bKeyRaw, keyCore))[17:]
	return nil
}

func (d *Decoder) readMetaData() error {
	if d.offsetMeta == 0 || d.offsetMeta+4 > d.fileLen {
		return errors.New("invalid meta file offset")
	}
	bMetaLen := d.file[d.offsetMeta : d.offsetMeta+4]
	iMetaLen := binary.LittleEndian.Uint32(bMetaLen)
	d.offsetCover = d.offsetMeta + 4 + iMetaLen
	if iMetaLen == 0 {
		return errors.New("no any meta file found")
	}

	// Why sub 22: Remove "163 key(Don't modify):"
	bKeyRaw := make([]byte, iMetaLen-22)
	for i := uint32(0); i < iMetaLen-22; i++ {
		bKeyRaw[i] = d.file[d.offsetMeta+4+22+i] ^ 0x63
	}

	cipherText, err := base64.StdEncoding.DecodeString(string(bKeyRaw))
	if err != nil {
		return errors.New("decode ncm meta failed: " + err.Error())
	}
	metaRaw := utils.PKCS7UnPadding(utils.DecryptAes128Ecb(cipherText, keyMeta))
	sepIdx := bytes.IndexRune(metaRaw, ':')
	if sepIdx == -1 {
		return errors.New("invalid ncm meta file")
	}

	d.metaType = string(metaRaw[:sepIdx])
	d.metaRaw = metaRaw[sepIdx+1:]
	return nil
}

func (d *Decoder) buildKeyBox() {
	box := make([]byte, 256)
	for i := 0; i < 256; i++ {
		box[i] = byte(i)
	}

	keyLen := len(d.key)
	var j byte
	for i := 0; i < 256; i++ {
		j = box[i] + j + d.key[i%keyLen]
		box[i], box[j] = box[j], box[i]
	}

	d.box = make([]byte, 256)
	var _i byte
	for i := 0; i < 256; i++ {
		_i = byte(i + 1)
		si := box[_i]
		sj := box[_i+si]
		d.box[i] = box[si+sj]
	}
}

func (d *Decoder) parseMeta() error {
	switch d.metaType {
	case "music":
		d.meta = new(RawMetaMusic)
		return json.Unmarshal(d.metaRaw, d.meta)
	case "dj":
		d.meta = new(RawMetaDJ)
		return json.Unmarshal(d.metaRaw, d.meta)
	default:
		return errors.New("unknown ncm meta type: " + d.metaType)
	}
}

func (d *Decoder) readCoverData() error {
	if d.offsetCover == 0 || d.offsetCover+13 > d.fileLen {
		return errors.New("invalid cover file offset")
	}

	coverLenStart := d.offsetCover + 5 + 4
	bCoverLen := d.file[coverLenStart : coverLenStart+4]

	iCoverLen := binary.LittleEndian.Uint32(bCoverLen)
	d.offsetAudio = coverLenStart + 4 + iCoverLen
	if iCoverLen == 0 {
		return nil
	}
	d.cover = d.file[coverLenStart+4 : coverLenStart+4+iCoverLen]
	return nil
}

func (d *Decoder) readAudioData() error {
	if d.offsetAudio == 0 || d.offsetAudio > d.fileLen {
		return errors.New("invalid audio offset")
	}
	audioRaw := d.file[d.offsetAudio:]
	audioLen := len(audioRaw)
	d.audio = make([]byte, audioLen)
	for i := uint32(0); i < uint32(audioLen); i++ {
		d.audio[i] = d.box[i&0xff] ^ audioRaw[i]
	}
	return nil
}

func (d *Decoder) Decode() error {
	if err := d.readKeyData(); err != nil {
		return fmt.Errorf("read key data failed: %w", err)
	}
	d.buildKeyBox()

	if err := d.readMetaData(); err != nil {
		return fmt.Errorf("read meta date failed: %w", err)
	}
	if err := d.parseMeta(); err != nil {
		return fmt.Errorf("parse meta failed: %w", err)
	}

	if err := d.readCoverData(); err != nil {
		return fmt.Errorf("parse ncm cover file failed: %w", err)
	}

	return d.readAudioData()
}

func (d *Decoder) GetAudioExt() string {
	if d.meta != nil {
		if format := d.meta.GetFormat(); format != "" {
			return "." + d.meta.GetFormat()
		}
	}
	return ""
}

func (d *Decoder) GetAudioData() []byte {
	return d.audio
}

func (d *Decoder) GetCoverImage(ctx context.Context) ([]byte, error) {
	if d.cover != nil {
		return d.cover, nil
	}
	imgURL := d.meta.GetAlbumImageURL()
	if d.meta != nil && !strings.HasPrefix(imgURL, "http") {
		return nil, nil // no cover image
	}

	// fetch cover image
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, imgURL, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("download image failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download image failed: unexpected http status %s", resp.Status)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("download image failed: %w", err)
	}
	return data, nil
}

func (d *Decoder) GetMeta() common.Meta {
	return d.meta
}

func init() {
	// Netease Mp3/Flac
	common.RegisterDecoder("ncm", false, NewDecoder)
}
