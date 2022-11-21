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
	"unlock-music.dev/cli/internal/logging"
	"unlock-music.dev/cli/internal/sniff"
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
			&cli.BoolFlag{Name: "supported-ext", Usage: "Show supported file extensions and exit", Required: false, Value: false},
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

	skipNoop := c.Bool("skip-noop")
	removeSource := c.Bool("remove-source")

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

	if inputStat.IsDir() {
		return dealDirectory(input, output, skipNoop, removeSource)
	} else {
		allDec := common.GetDecoder(inputStat.Name(), skipNoop)
		if len(allDec) == 0 {
			logger.Fatal("skipping while no suitable decoder")
		}
		return tryDecFile(input, output, allDec, removeSource)
	}

}
func dealDirectory(inputDir string, outputDir string, skipNoop bool, removeSource bool) error {
	items, err := os.ReadDir(inputDir)
	if err != nil {
		return err
	}
	for _, item := range items {
		if item.IsDir() {
			continue
		}
		allDec := common.GetDecoder(item.Name(), skipNoop)
		if len(allDec) == 0 {
			logger.Info("skipping while no suitable decoder", zap.String("file", item.Name()))
			continue
		}

		filePath := filepath.Join(inputDir, item.Name())
		err := tryDecFile(filePath, outputDir, allDec, removeSource)
		if err != nil {
			logger.Error("conversion failed", zap.String("source", filePath), zap.Error(err))
		}
	}
	return nil
}

func tryDecFile(inputFile string, outputDir string, allDec []common.NewDecoderFunc, removeSource bool) error {
	file, err := os.Open(inputFile)
	if err != nil {
		return err
	}
	defer file.Close()

	decParams := &common.DecoderParams{
		Reader:    file,
		Extension: filepath.Ext(inputFile),
		FilePath:  inputFile,
		Logger:    logger.With(zap.String("source", inputFile)),
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

	header := bytes.NewBuffer(nil)
	_, err = io.CopyN(header, dec, 64)
	if err != nil {
		return fmt.Errorf("read header failed: %w", err)
	}

	outExt := sniff.AudioExtensionWithFallback(header.Bytes(), ".mp3")
	inFilename := strings.TrimSuffix(filepath.Base(inputFile), filepath.Ext(inputFile))

	outPath := filepath.Join(outputDir, inFilename+outExt)
	outFile, err := os.OpenFile(outPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer outFile.Close()

	if _, err := io.Copy(outFile, header); err != nil {
		return err
	}
	if _, err := io.Copy(outFile, dec); err != nil {
		return err
	}

	if coverGetter, ok := dec.(common.CoverImageGetter); ok {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		cover, err := coverGetter.GetCoverImage(ctx)
		if err != nil {
			logger.Warn("get cover image failed", zap.Error(err))
		} else if imgExt, ok := sniff.ImageExtension(cover); !ok {
			logger.Warn("sniff cover image type failed", zap.Error(err))
		} else {
			coverPath := filepath.Join(outputDir, inFilename+imgExt)
			err = os.WriteFile(coverPath, cover, 0644)
			if err != nil {
				logger.Warn("write cover image failed", zap.Error(err))
			}
		}
	}

	if audioMetaGetter, ok := dec.(common.AudioMetaGetter); ok {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		meta, err := audioMetaGetter.GetAudioMeta(ctx)
		if err != nil {
			logger.Warn("get audio meta failed", zap.Error(err))
		} else {
			logger.Info("audio metadata",
				zap.String("title", meta.GetTitle()),
				zap.Strings("artists", meta.GetArtists()),
				zap.String("album", meta.GetAlbum()),
			)
		}
	}

	// if source file need to be removed
	if removeSource {
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
