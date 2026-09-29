# Document Archiving

A Windows PowerShell workflow for turning scanned TIFF documents into clean, consistently sized PDF files.

The project is intended to provide a flexible, repeatable alternative to manually correcting every scan in an image editor such as Photoshop. It combines IrfanView with open-source command-line tools to extract, straighten, crop and assemble scanned pages while keeping the working images in a lossless TIFF workflow.

## Project status

The main processing workflow is now implemented and ready for real-document testing.

The code should be considered **pre-release** while a broader selection of scanned documents, page sizes, orientations and TIFF compression types is tested. Keep the original scans until the resulting TIFF files and PDFs have been checked.

## What it does

Each document is processed through a resumable five-stage folder workflow:

1. **Source** — accepts one folder per document containing one or more TIFF files.
2. **Extracted** — extracts multipage TIFFs into ordered, single-page TIFF files.
3. **Deskewed** — detects and corrects page rotation with Deskew.
4. **Cropped** — centre-crops each page to the closest configured paper size.
5. **PDFs** — combines the finished TIFF pages into a PDF named after the document folder.

The processing stages can be enabled or disabled independently. A document is skipped when its destination folder already exists, allowing an interrupted run to be resumed without reprocessing completed folders.

This is an image-processing and PDF-assembly workflow. It does not currently perform OCR or create searchable text layers.

## Why TIFF?

TIFF supports high-resolution scanned pages and lossless compression. The aim is to avoid repeated conversion through lossy formats such as JPEG.

Deskewing and cropping necessarily alter pixel positions, so those geometric operations are not mathematically lossless. The resulting pages remain in a lossless TIFF format, however, avoiding additional JPEG-style generational loss.

### Compression options

| Setting | IrfanView value | Intended use |
| --- | ---: | --- |
| `LZW` | `1` | Default. Lossless general-purpose compression suitable for grayscale, colour and many monochrome scans. |
| `CCITT Fax 4` | `4` | Lossless and highly efficient for true 1-bit black-and-white document scans. It is not suitable for ordinary grayscale or colour pages. |
| `None` | `0` | Uncompressed TIFF. Preserves the same image information as lossless compression but produces much larger files. |

Set `$Set_Compression` to `"Y"` to use `$Compression`. When it is `"n"`, the script defaults to LZW.

The script locates IrfanView's active `i_view64.ini`, including an installer-configured `INI_Folder` redirect, creates a one-time `i_view64.ini.original.bak`, preserves the original Unicode encoding, updates only the required TIFF settings and verifies the saved values.

## Currently supported page sizes

The crop profiles assume source images of approximately **600 DPI**. Select the required set with `$PaperProfile` in `doc-archiving.ps1`.

| Paper profile | Page type | Recognition dimensions | Finished dimensions |
| --- | --- | ---: | ---: |
| Standard | A4 | 4792 × 6846 px, 330 px combined tolerance | 4792 × 6846 px |
| Standard | A3 | 9268 × 6846 px, 600 px combined tolerance | 9268 × 6846 px |
| B&O-Service-Manual | B&O-Standard | 4850–5050 × 6780–7000 px | 4950 × 6900 px |
| B&O-Service-Manual | B&O-Wide | 9250–9500 × 6750–7000 px | 9413 × 6900 px |
| B&O-Service-Manual | B&O-Foldout | At least 15000 × 6750–7050 px | Original width × 6900 px |

The B&O profile deliberately separates recognition dimensions from finished dimensions. This allows scanner edge cleaning and deskew canvas expansion to be recognised while producing consistent PDF page sizes. Standard and wide pages are centred, cropped where larger than the target and padded where smaller. Foldouts retain their individual width while their height is normalised to 6900 pixels.

Portrait and landscape orientations are both considered. Pages outside the selected profile are reported as `[REVIEW]` and left unprocessed.

## Requirements

- Windows
- Windows PowerShell 5.1 or later
- [IrfanView 64-bit](https://www.irfanview.com/), currently expected at:

  ```text
  C:\Program Files\IrfanView\i_view64.exe
  ```

- [Deskew](https://github.com/galfar/deskew), compiled manually from the current source
- Internet access on the first run so the script can download `img2pdf` 0.6.0
- Permission to run local PowerShell scripts

IrfanView is freeware rather than open source. Deskew and img2pdf are open-source projects. Users remain responsible for checking all dependency licences for their intended use.

## Important: build Deskew from source

For now, do **not** rely on the old precompiled Deskew release included upstream. The published CLI release is from 2019 and its Windows binary has proved unsuitable for this workflow.

Compile the current source from:

<https://github.com/galfar/deskew>

Deskew is written in Object Pascal and can be built with Free Pascal, Lazarus or Delphi. The upstream project provides project files for Lazarus and Delphi, plus a Windows build script.

### Command-line build with Free Pascal

1. Install the current 64-bit Free Pascal compiler and ensure `fpc.exe` is available on `PATH`.
2. Clone or download the Deskew repository.
3. Open a command prompt in its `Scripts` directory.
4. Run:

   ```bat
   Compile.bat
   ```

The upstream script compiles `deskew.lpr` and writes the executable into the repository's `Bin` directory.

Copy the newly compiled 64-bit executable into this project as:

```text
apps\deskew\bin\deskew.exe
```

The required project layout is:

```text
doc-archiving\
├── doc-archiving.ps1
├── lib\
└── apps\
    └── deskew\
        └── bin\
            └── deskew.exe
```

The `apps` directory is excluded by `.gitignore`, so locally compiled binaries are not committed.

## Initial setup

Clone the repository and install IrfanView 64-bit.

If PowerShell script execution is disabled, configure an appropriate policy for your user account:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

or use a one-time process override:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\GitHub\doc-archiving\doc-archiving.ps1"
```

Compile Deskew and put `deskew.exe` in:

```text
apps\deskew\bin\
```

On its first run, the script creates the working directories and downloads `img2pdf`:

```text
1 - source\
2 - extracted\
3 - deskewed\
4 - cropped\
5 - pdfs\
apps\
logs\
```

## Preparing documents

Create one subfolder beneath `1 - source` for each document:

```text
1 - source\
└── example-document\
    └── original-scan.tif
```

The source may be a multipage TIFF or multiple TIFF files. Extracted pages are renamed sequentially as `001.tif`, `002.tif` and so on.

### Optional mixed colour and black-and-white crop processing

Deskewed pages may remain directly inside their document folder, preserving the original behaviour. Alternatively, create either or both of these immediate subfolders beneath a deskewed document:

```text
3 - deskewed\\
└── example-document\\
    ├── colour\\
    │   ├── 001.tif
    │   └── 002.tif
    └── black-white\\
        ├── 003.tif
        └── 004.tif
```

During cropping:

- files in `colour\\` retain their colour depth and use lossless LZW compression;
- files in `black-white\\` are converted to true 1-bit monochrome without dithering and use CCITT Fax 4 compression;
- files directly inside the document folder continue using the configured/default compression;
- the special folders are flattened back into one cropped document folder, preserving filename-based PDF page ordering.

The crop stage checks the complete flattened destination plan before writing anything. Duplicate filenames across the document root, `colour\\` and `black-white\\` cause the run to stop rather than overwrite a page. Black-and-white output is verified as 1 BPP, and readable TIFF compression tags are checked against the requested compression.

The final output will be:

```text
5 - pdfs\
└── example-document.pdf
```

Keep a separate archival copy of the original scans. The working folders are excluded from Git and are not a substitute for a backup.

## Running the pipeline

Processing is controlled by switches near the top of `doc-archiving.ps1`:

```powershell
$Run_TIFF_Extraction = "Y"
$Run_Deskew          = "Y"
$Run_Crop            = "Y"
$Combine_to_PDF      = "Y"
```

Then run:

```powershell
& "C:\GitHub\doc-archiving\doc-archiving.ps1"
```

Before PDF creation, the script pauses so the processed pages can be reviewed.

If a document needs to be reprocessed, remove its corresponding folder from the relevant destination stage and rerun that stage. Existing destination folders are intentionally skipped.

## Processing details

Deskew now uses a guarded two-pass process:

1. Detect the angle without changing the source page.
2. Optionally exclude page-edge margins when using a Deskew build that supports the `-m` option.
3. Copy pages below 0.10 degrees unchanged.
4. Correct pages from 0.10 through 2.00 degrees.
5. Copy pages above 2.00 degrees unchanged and mark them `[REVIEW]` in the log.
6. Copy the original page unchanged if detection, angle parsing or output generation fails.

The detector still searches up to 10 degrees so large suspicious results are identified rather than silently clamped. Accepted pages are deskewed using automatic threshold detection, a white background and the input TIFF compression scheme where supported.

These safety values are grouped under `### Deskew safety settings` in `doc-archiving.ps1`. Margin exclusion is disabled by default for compatibility with older Deskew command-line builds; set `$DeskewDetectionMargins = "5,5,%"` only after confirming that the local executable supports `-m`. This favours preserving a slightly skewed source page over applying a destructive false rotation.

Cropping compares each deskewed page only with the selected `$PaperProfile`, including rotated orientation. A matching page is centred and cropped or padded to its configured output dimensions; every written TIFF is reopened and its dimensions are verified. Optional `colour` and `black-white` folders select LZW or 1-bit CCITT Fax 4 output and are flattened into the cropped document root after duplicate-name validation.

`img2pdf` then assembles the ordered TIFF pages into the final PDF.

## Logging and safety

Runtime activity is written to:

```text
logs\doc-archiving.log
```

The script also:

- creates required folders automatically;
- checks that IrfanView is installed;
- identifies the operating-system architecture;
- discovers the active IrfanView INI location;
- refuses to edit the INI while IrfanView is running;
- backs up the original INI once;
- preserves its encoding and unrelated settings;
- verifies every INI value after editing.

## Current limitations

- Crop profiles are currently tailored to a 600 DPI workflow.
- Deskew must be compiled and installed manually.
- IrfanView is currently expected in its default 64-bit installation path.
- Processing switches are edited directly in the script.
- PDF output is image-only; OCR and PDF/A conversion are not currently performed.
- Real-world document testing is still in progress.

## Background

This project unifies and develops several earlier scripts:

- [Doc-Archiving](https://github.com/theretrobristolian/Scripts/tree/main/Doc-Archiving)
- [Align-TIF](https://github.com/theretrobristolian/Scripts/tree/main/Align-TIF)
- [Deskew](https://github.com/theretrobristolian/Scripts/tree/main/Deskew)
- [TIF-Converter](https://github.com/theretrobristolian/Scripts/tree/main/TIF-Converter)

The objective is a practical, flexible route from a high-quality source scan to a straight, consistently sized and professional-looking PDF without requiring a heavyweight commercial image-editing workflow.
