package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"sort"
	"strings"
	"time"

	"github.com/urfave/cli/v2"
	"go.uber.org/zap"

	"unlock-music.dev/cli/algo/common"
	_ "unlock-music.dev/cli/algo/kgm"
	_ "unlock-music.dev/cli/algo/kwm"
	_ "unlock-music.dev/cli/algo/ncm"
	_ "unlock-music.dev/cli/algo/qmc"
	_ "unlock-music.dev/cli/algo/tm"
	_ "unlock-music.dev/cli/algo/xiami"
	_ "unlock-music.dev/cli/algo/ximalaya"
	"unlock-music.dev/cli/internal/ffmpeg"
	"unlock-music.dev/cli/internal/logging"
	"unlock-music.dev/cli/internal/sniff"
	"unlock-music.dev/cli/internal/utils"
)

var AppVersion = "v0.0.6"

var logger, _ = logging.NewZapLogger() // TODO: inject logger to application, instead of using global logger

func main() {
	module, ok := debug.ReadBuildInfo()
	if ok && module.Main.Version != "(devel)" {
		AppVersion = module.Main.Version
	}
	app := cli.App{
		Name:     "Unlock Music CLI",
		HelpName: "um",
		Usage:    "Unlock your encrypted music file https://git.unlock-music.dev/um/cli",
		Version:  fmt.Sprintf("%s (%s,%s/%s)", AppVersion, runtime.Version(), runtime.GOOS, runtime.GOARCH),
		Flags: []cli.Flag{
			&cli.StringFlag{Name: "input", Aliases: []string{"i"}, Usage: "path to input file or dir", Required: false},
			&cli.StringFlag{Name: "output", Aliases: []string{"o"}, Usage: "path to output dir", Required: false},
			&cli.BoolFlag{Name: "remove-source", Aliases: []string{"rs"}, Usage: "remove source file", Required: false, Value: false},
			&cli.BoolFlag{Name: "skip-noop", Aliases: []string{"n"}, Usage: "skip noop decoder", Required: false, Value: true},
			&cli.BoolFlag{Name: "update-metadata", Usage: "update metadata & album art from network", Required: false, Value: false},
			&cli.BoolFlag{Name: "overwrite", Usage: "overwrite output file without asking", Required: false, Value: false},

			&cli.BoolFlag{Name: "supported-ext", Usage: "show supported file extensions and exit", Required: false, Value: false},
		},

		Action:          appMain,
		Copyright:       fmt.Sprintf("Copyright (c) 2020 - %d Unlock Music https://git.unlock-music.dev/um/cli/src/branch/master/LICENSE", time.Now().Year()),
		HideHelpCommand: true,
		UsageText:       "um [-o /path/to/output/dir] [--extra-flags] [-i] /path/to/input",
	}
	err := app.Run(os.Args)
	if err != nil {
		logger.Fatal("run app failed", zap.Error(err))
	}
}
func printSupportedExtensions() {
	var exts []string
	for ext := range common.DecoderRegistry {
		exts = append(exts, ext)
	}
	sort.Strings(exts)
	for _, ext := range exts {
		fmt.Printf("%s: %d\n", ext, len(common.DecoderRegistry[ext]))
	}
}
func appMain(c *cli.Context) (err error) {
	if c.Bool("supported-ext") {
		printSupportedExtensions()
		return nil
	}
	input := c.String("input")
	if input == "" {
		switch c.Args().Len() {
		case 0:
			input, err = os.Getwd()
			if err != nil {
				return err
			}
		case 1:
			input = c.Args().Get(0)
		default:
			return errors.New("please specify input file (or directory)")
		}
	}

	output := c.String("output")
	if output == "" {
		var err error
		output, err = os.Getwd()
		if err != nil {
			return err
		}
		if input == output {
			return errors.New("input and output path are same")
		}
	}

	inputStat, err := os.Stat(input)
	if err != nil {
		return err
	}

	outputStat, err := os.Stat(output)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			err = os.MkdirAll(output, 0755)
		}
		if err != nil {
			return err
		}
	} else if !outputStat.IsDir() {
		return errors.New("output should be a writable directory")
	}

	proc := &processor{
		outputDir:       output,
		skipNoopDecoder: c.Bool("skip-noop"),
		removeSource:    c.Bool("remove-source"),
		updateMetadata:  c.Bool("update-metadata"),
		overwriteOutput: c.Bool("overwrite"),
	}

	if inputStat.IsDir() {
		return proc.processDir(input)
	} else {
		return proc.processFile(input)
	}

}

type processor struct {
	outputDir string

	skipNoopDecoder bool
	removeSource    bool
	updateMetadata  bool
	overwriteOutput bool
}

func (p *processor) processDir(inputDir string) error {
	items, err := os.ReadDir(inputDir)
	if err != nil {
		return err
	}
	for _, item := range items {
		if item.IsDir() {
			continue
		}

		filePath := filepath.Join(inputDir, item.Name())
		allDec := common.GetDecoder(filePath, p.skipNoopDecoder)
		if len(allDec) == 0 {
			logger.Info("skipping while no suitable decoder", zap.String("source", item.Name()))
			continue
		}

		if err := p.process(filePath, allDec); err != nil {
			logger.Error("conversion failed", zap.String("source", item.Name()), zap.Error(err))
		}
	}
	return nil
}

func (p *processor) processFile(filePath string) error {
	allDec := common.GetDecoder(filePath, p.skipNoopDecoder)
	if len(allDec) == 0 {
		logger.Fatal("skipping while no suitable decoder")
	}
	return p.process(filePath, allDec)
}

func (p *processor) process(inputFile string, allDec []common.NewDecoderFunc) error {
	file, err := os.Open(inputFile)
	if err != nil {
		return err
	}
	defer file.Close()
	logger := logger.With(zap.String("source", inputFile))

	decParams := &common.DecoderParams{
		Reader:    file,
		Extension: filepath.Ext(inputFile),
		FilePath:  inputFile,
		Logger:    logger,
	}

	var dec common.Decoder
	for _, decFunc := range allDec {
		dec = decFunc(decParams)
		if err := dec.Validate(); err == nil {
			break
		} else {
			logger.Warn("try decode failed", zap.Error(err))
			dec = nil
		}
	}
	if dec == nil {
		return errors.New("no any decoder can resolve the file")
	}

	params := &ffmpeg.UpdateMetadataParams{}

	header := bytes.NewBuffer(nil)
	_, err = io.CopyN(header, dec, 64)
	if err != nil {
		return fmt.Errorf("read header failed: %w", err)
	}
	audio := io.MultiReader(header, dec)
	params.AudioExt = sniff.AudioExtensionWithFallback(header.Bytes(), ".mp3")

	if p.updateMetadata {
		if audioMetaGetter, ok := dec.(common.AudioMetaGetter); ok {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()

			// since ffmpeg doesn't support multiple input streams,
			// we need to write the audio to a temp file.
			// since qmc decoder doesn't support seeking & relying on ffmpeg probe, we need to read the whole file.
			// TODO: support seeking or using pipe for qmc decoder.
			params.Audio, err = utils.WriteTempFile(audio, params.AudioExt)
			if err != nil {
				return fmt.Errorf("updateAudioMeta write temp file: %w", err)
			}
			defer os.Remove(params.Audio)

			params.Meta, err = audioMetaGetter.GetAudioMeta(ctx)
			if err != nil {
				logger.Warn("get audio meta failed", zap.Error(err))
			}

			if params.Meta == nil { // reset audio meta if failed
				audio, err = os.Open(params.Audio)
				if err != nil {
					return fmt.Errorf("updateAudioMeta open temp file: %w", err)
				}
			}
		}
	}

	if p.updateMetadata && params.Meta != nil {
		if coverGetter, ok := dec.(common.CoverImageGetter); ok {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()

			if cover, err := coverGetter.GetCoverImage(ctx); err != nil {
				logger.Warn("get cover image failed", zap.Error(err))
			} else if imgExt, ok := sniff.ImageExtension(cover); !ok {
				logger.Warn("sniff cover image type failed", zap.Error(err))
			} else {
				params.AlbumArtExt = imgExt
				params.AlbumArt = cover
			}
		}
	}

	inFilename := strings.TrimSuffix(filepath.Base(inputFile), filepath.Ext(inputFile))
	outPath := filepath.Join(p.outputDir, inFilename+params.AudioExt)

	if !p.overwriteOutput {
		_, err := os.Stat(outPath)
		if err == nil {
			return fmt.Errorf("output file %s is already exist", outPath)
		} else if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("stat output file failed: %w", err)
		}
	}

	if params.Meta == nil {
		outFile, err := os.OpenFile(outPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			return err
		}
		defer outFile.Close()

		if _, err := io.Copy(outFile, audio); err != nil {
			return err
		}
		outFile.Close()

	} else {
		ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
		defer cancel()

		if err := ffmpeg.UpdateMeta(ctx, outPath, params); err != nil {
			return err
		}
	}

	// if source file need to be removed
	if p.removeSource {
		err := os.RemoveAll(inputFile)
		if err != nil {
			return err
		}
		logger.Info("successfully converted, and source file is removed", zap.String("source", inputFile), zap.String("destination", outPath))
	} else {
		logger.Info("successfully converted", zap.String("source", inputFile), zap.String("destination", outPath))
	}

	return nil
}
