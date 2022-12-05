package ffmpeg

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"unlock-music.dev/cli/algo/common"
)

func ExtractAlbumArt(ctx context.Context, rd io.Reader) (*bytes.Buffer, error) {
	cmd := exec.CommandContext(ctx, "ffmpeg",
		"-i", "pipe:0", // input from stdin
		"-an",              // disable audio
		"-codec:v", "copy", // copy video(image) codec
		"-f", "image2", // use image2 muxer
		"pipe:1", // output to stdout
	)

	cmd.Stdin = rd
	stdout, stderr := &bytes.Buffer{}, &bytes.Buffer{}
	cmd.Stdout, cmd.Stderr = stdout, stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("ffmpeg run: %w", err)
	}

	return stdout, nil
}

type UpdateMetadataParams struct {
	Audio    io.Reader // required
	AudioExt string    // required

	Meta common.AudioMeta // required

	AlbumArt    io.Reader // optional
	AlbumArtExt string    // required if AlbumArt is not nil
}

func UpdateAudioMetadata(ctx context.Context, params *UpdateMetadataParams) (*bytes.Buffer, error) {
	builder := newFFmpegBuilder()
	builder.SetFlag("y") // overwrite output file

	out := newOutputBuilder("pipe:1")                        // use stdout as output
	out.AddOption("f", encodeFormatFromExt(params.AudioExt)) // use mp3 muxer
	builder.AddOutput(out)

	// since ffmpeg doesn't support multiple input streams,
	// we need to write the audio to a temp file
	audioPath, err := writeTempFile(params.Audio, params.AudioExt)
	if err != nil {
		return nil, fmt.Errorf("updateAudioMeta write temp file: %w", err)
	}
	defer os.Remove(audioPath)

	// input audio -> output audio
	builder.AddInput(newInputBuilder(audioPath)) // input 0: audio
	out.AddOption("map", "0:a")
	out.AddOption("codec:a", "copy")

	// input cover -> output cover
	if params.AlbumArt != nil &&
		params.AudioExt != ".wav" /* wav doesn't support attached image */ {

		// write cover to temp file
		artPath, err := writeTempFile(params.AlbumArt, params.AlbumArtExt)
		if err != nil {
			return nil, fmt.Errorf("updateAudioMeta write temp file: %w", err)
		}
		defer os.Remove(artPath)

		builder.AddInput(newInputBuilder(artPath)) // input 1: cover
		out.AddOption("map", "1:v")

		switch params.AudioExt {
		case ".ogg": // ogg only supports theora codec
			out.AddOption("codec:v", "libtheora")
		case ".m4a": // .m4a(mp4) requires set codec, disposition, stream metadata
			out.AddOption("codec:v", "mjpeg")
			out.AddOption("disposition:v", "attached_pic")
			out.AddMetadata("s:v", "title", "Album cover")
			out.AddMetadata("s:v", "comment", "Cover (front)")
		default: // other formats use default behavior
		}
	}

	// set file metadata
	album := params.Meta.GetAlbum()
	if album != "" {
		out.AddMetadata("", "album", album)
	}

	title := params.Meta.GetTitle()
	if album != "" {
		out.AddMetadata("", "title", title)
	}

	artists := params.Meta.GetArtists()
	if len(artists) != 0 {
		// TODO: it seems that ffmpeg doesn't support multiple artists
		out.AddMetadata("", "artist", strings.Join(artists, " / "))
	}

	// execute ffmpeg
	cmd := builder.Command(ctx)
	stdout, stderr := &bytes.Buffer{}, &bytes.Buffer{}
	cmd.Stdout, cmd.Stderr = stdout, stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("ffmpeg run: %w", err)
	}

	return stdout, nil
}

func writeTempFile(rd io.Reader, ext string) (string, error) {
	audioFile, err := os.CreateTemp("", "*"+ext)
	if err != nil {
		return "", fmt.Errorf("ffmpeg create temp file: %w", err)
	}

	if _, err := io.Copy(audioFile, rd); err != nil {
		return "", fmt.Errorf("ffmpeg write temp file: %w", err)
	}

	if err := audioFile.Close(); err != nil {
		return "", fmt.Errorf("ffmpeg close temp file: %w", err)
	}

	return audioFile.Name(), nil
}

// encodeFormatFromExt returns the file format name the recognized & supporting encoding by ffmpeg.
func encodeFormatFromExt(ext string) string {
	switch ext {
	case ".flac":
		return "flac" // raw FLAC
	case ".mp3":
		return "mp3" // MP3 (MPEG audio layer 3)
	case ".ogg":
		return "ogg" // Ogg
	case ".m4a":
		return "ipod" // iPod H.264 MP4 (MPEG-4 Part 14)
	case ".wav":
		return "wav" // WAV / WAVE (Waveform Audio)
	case ".aac":
		return "adts" // ADTS AAC (Advanced Audio Coding)
	case ".wma":
		return "asf" // ASF (Advanced / Active Streaming Format)
	default:
		return ""
	}
}
