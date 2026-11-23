# File Converter (Flutter, Android, offline)

Converts files on the phone. It needs no internet and no server.

| From | To |
|---|---|
| EPUB | TXT, PDF (each chapter starts on a new page) |
| DOCX | TXT, PDF |
| TXT | PDF |
| JPG, PNG, WEBP, BMP, GIF, TIFF | JPG, PNG, BMP, PDF (several images can go into one PDF) |

## Setup (Windows, PowerShell)

```powershell
cd C:\Users\bilal\github
# unzip file_converter.zip here, then:
cd file_converter
flutter create --platforms android --org com.bilal .   # adds the android/ folder, keeps lib/ and pubspec.yaml
flutter pub get
flutter analyze
flutter run                                            # with your phone plugged in (USB debugging on)
```

To build an APK you can install:

```powershell
flutter build apk --release
# output: build\app\outputs\flutter-apk\app-release.apk
```

To change the app name shown on the phone, edit `android:label` in
`android/app/src/main/AndroidManifest.xml`.

If `flutter pub get` reports version conflicts, run `flutter pub upgrade --major-versions`.

## Project layout

```
lib/
  main.dart                      app + theme
  models.dart                    formats, which input -> which outputs
  screens/home_screen.dart       the UI
  services/conversion_service.dart  runs conversions in a background isolate
  services/file_service.dart     pick / save as / share
  converters/
    epub_converter.dart          container.xml -> .opf -> spine -> chapter text
    docx_converter.dart          word/document.xml -> text
    image_converter.dart         decode / encode images (pure Dart)
    pdf_builder.dart             text PDF and image PDF
    text_utils.dart              HTML->text, encoding detection, cleanup
assets/fonts/DejaVuSans.ttf      Unicode font so PDFs show Arabic, accents, etc.
```

## Adding a new conversion

1. Add the target to `targetsFor()` in `models.dart`. For a new input type, also add it to `InputKind` and `inputKindOf()`.
2. Handle it in `_convertOne()` in `conversion_service.dart`.

## Known limits

- DRM-protected EPUBs (from stores like Kindle or Kobo) can't be read. The app shows an error for them.
- The `image` package can read WEBP but can't write it, so WEBP isn't offered as an output.
- Old `.doc` files (before 2007) aren't supported. Only `.docx` is.
- PDF → anything isn't included yet. It's the hardest direction. A good next step is PDF → TXT using `syncfusion_flutter_pdf`.
- Big photos (12 MP and up) take a few seconds each because decoding is pure Dart. This runs off the UI thread.
