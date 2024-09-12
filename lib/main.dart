import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';

import 'package:simple_frame_app/camera_settings.dart';
import 'package:simple_frame_app/image_data_response.dart';
import 'package:image_mlkit_converter/image_mlkit_converter.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/sprite.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState {

  // the image to show
  Image? _image;
  bool? _isHotdog;
  final Stopwatch _stopwatch = Stopwatch();

  late final ImageLabeler _imageLabeler;

  MainAppState() {
    Logger.root.level = Level.FINE;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();

    // We have a 30% threshold for hotdogs so we exclude burgers etc
    final ImageLabelerOptions options = ImageLabelerOptions(confidenceThreshold: 0.30);
    _imageLabeler = ImageLabeler(options: options);
  }

  @override
  void dispose() {
    // clean up the labeler
    _imageLabeler.close();

    super.dispose();
  }

  /// Strips the Alpha byte out of a list of RGBA colors
  /// Takes a Uint8List of length 4n made of RGBA bytes, and takes the first 3 bytes out of each 4 (RGB)
  Uint8List _extractRGB(Uint8List rgba) {
    // The output list will have 3/4 the length of the input list
    Uint8List rgb = Uint8List((rgba.length * 3) ~/ 4);

    int rgbIndex = 0;
    for (int i = 0; i < rgba.length; i += 4) {
      rgb[rgbIndex++] = rgba[i];     // R
      rgb[rgbIndex++] = rgba[i + 1]; // G
      rgb[rgbIndex++] = rgba[i + 2]; // B
    }

    return rgb;
  }

  /// Loops over each of the sprites in the assets/sprites directory (and declared in pubspec.yaml) and returns an entry with
  /// each sprite associated with a message_type key: the two hex digits in its filename,
  /// e.g. 'assets/sprites/1f_mysprite.png' has a message type of 0x1f. This message is used to key the messages in the frameside lua app
  Map<int, String> _filterSpriteAssets(List<String> files) {
    var spriteFiles = files.where((String pathFile) => pathFile.startsWith('assets/sprites/') && pathFile.endsWith('.png')).toList();

    // Create the map from hexadecimal integer prefix to sprite name
    final Map<int, String> spriteMap = {};

    for (final String sprite in spriteFiles) {
      // Extract the part of the filename without the directory and extension
      final String fileName = sprite.split('/').last; // e.g., "12_spriteone.png"

      // Extract the hexadecimal prefix and the sprite name
      final String hexPrefix = fileName.split('_').first; // e.g., "12"

      // Convert the hexadecimal prefix to an integer
      final int? hexValue = int.tryParse(hexPrefix, radix: 16);

      if (hexValue == null) {
        _log.severe('invalid hex prefix: $hexPrefix for asset $sprite');
      }
      else {
        // Add the hex value and sprite to the map
        spriteMap[hexValue] = sprite;
      }
    }

    return spriteMap;
  }

  /// Loops over each of the filtered sprites in the assets/sprites directory and sends each sprite with the message_type
  /// indicated as two hex digits in its filename, e.g. 'assets/sprites/1f_mysprite.png' has a message code of 0x1f
  /// Sprites should be PNGs with palettes of up to 2, 4, or 16 colors (1-, 2-, or 4-bit indexed palettes)
  /// Alpha channel (4th-RGBA), if present, is dropped before sending to Frame (RGB only, but color 0 is VOID)
  Future<void> _uploadSprites(Map<int, String> spriteMap) async {
    for (var entry in spriteMap.entries) {
      try {
        Sprite sprite = spriteFromPngBytes(Uint8List.sublistView(await rootBundle.load(entry.value)));

        // send sprite to Frame with its associated message type
        // FIXME reinstate when Frame is back
        //await frame!.sendMessage(entry.key, sprite.pack());
      }
      catch (e) {
        _log.severe('$e');
      }
    }
  }

  /// Sprites should be PNGs with palettes of up to 2, 4, or 16 colors (1-, 2-, or 4-bit indexed palettes)
  /// Alpha channel (4th-RGBA), if present, is dropped before sending to Frame (RGB only, but color 0 is VOID)
  Sprite spriteFromPngBytes(Uint8List pngBytes) {
    var imgPng = img.PngDecoder().decode(pngBytes);

    if (imgPng != null && imgPng.hasPalette && imgPng.palette!.numColors <= 16) {

      // resize the image if it's too big - we really shouldn't have to do this for project sprites, just user-picked images
      if (imgPng.width > 640 || imgPng.height > 400) {
        // use nearest interpolation, we can't use any interpretation that averages colors
        imgPng = img.copyResize(imgPng, width: 640, height: 400, maintainAspect: true, interpolation: img.Interpolation.nearest);
      }

      // we can process RGB or RGBA format palettes, but any others we just exclude here
      if (imgPng.palette!.numChannels == 3 || imgPng.palette!.numChannels == 4) {

        late Sprite sprite;

        if (imgPng.palette!.numChannels == 3) {
          sprite = Sprite(imgPng.width, imgPng.height, imgPng.palette!.numColors, imgPng.palette!.toUint8List(), imgPng.data!.toUint8List());
        }
        else if (imgPng.palette!.numChannels == 4) {
          // strip out the alpha channel from the palette
          sprite = Sprite(imgPng.width, imgPng.height, imgPng.palette!.numColors, _extractRGB(imgPng.palette!.toUint8List()), imgPng.data!.toUint8List());
        }

        _log.fine('Sprite: ${imgPng.width} x ${imgPng.height}, ${imgPng.palette!.numColors} cols, ${sprite.pack().length} bytes');
        return sprite;
      }
      else {
        throw Exception('PNG colors must have 3 or 4 channels to be converted to a sprite');
      }
    }
    else {
      throw Exception('PNG must be a valid PNG image with a palette (indexed color) and 16 colors or fewer to be converted to a sprite');
    }
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    // keep looping, waiting for photo to be sent from Frame triggered by a user tap
    while (currentState == ApplicationState.running) {

      try {
        // send the lua command to request a photo from the Frame
        _stopwatch.reset();
        _stopwatch.start();
        // FIXME no, don't request one
        //await frame!.sendDataRaw(CameraSettingsMsg.pack(2, 0, 0, 0.0, 0.1, 6000, 1.0, 248));

        // FIXME move to simpleFrameApp.startApplication
        // load all the Sprites from assets/sprites
        await _uploadSprites(_filterSpriteAssets((await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets()));

        // synchronously await the image response encoded as a jpeg
        // FIXME no, test to see if there's an image ready or not, otherwise sleep and loop around again
        //Uint8List imageData = await imageDataResponse(frame!.dataResponse, 50).first;

        // FIXME for now let's pick a photo
        // Open the file picker
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg'],
        );

        Uint8List imageData;
        if (result != null) {
          File file = File(result.files.single.path!);

          // Read the file content and split into lines
          imageData = await file.readAsBytes();
        }
        else {
          _log.fine('User did not select a file');
          currentState = ApplicationState.ready;
          if (mounted) setState(() {});
          return;
        }

        // received a whole-image Uint8List with jpeg header and footer included
        _stopwatch.stop();

        try {
          // NOTE: Frame camera is rotated 90 degrees clockwise, so if we need to make it upright for image processing:
          // import 'package:image/image.dart' as image_lib;
          // image_lib.Image? im = image_lib.decodeJpg(imageData);
          // im = image_lib.copyRotate(im, angle: 270);

          _log.fine('Image file size in bytes: ${imageData.length}, elapsedMs: ${_stopwatch.elapsedMilliseconds}');

          // update Widget UI
          setState(() {
            _image = Image.memory(imageData, gaplessPlayback: true,);
          });

          // Perform vision processing pipeline
          // will sometimes throw an Exception on decoding, but doesn't return null
          _stopwatch.reset();
          _stopwatch.start();
          img.Image im = img.decodeJpg(imageData)!;
          _stopwatch.stop();
          _log.fine('Jpeg decoding took: ${_stopwatch.elapsedMilliseconds} ms');

          // Android mlkit needs NV21 InputImage format
          // iOS mlkit needs bgra8888 InputImage format
          // In both cases orientation metadata is passed to mlkit, so no need to bake in a rotation
          _stopwatch.reset();
          _stopwatch.start();
          // Frame images are rotated 90 degrees clockwise so let ML Kit know
          InputImage mlkitImage = ImageMlkitConverter.imageToMlkitInputImage(im, InputImageRotation.rotation90deg);
          _stopwatch.stop();
          _log.fine('NV21/BGRA8888 conversion took: ${_stopwatch.elapsedMilliseconds} ms');

          // run the image labeler
          _stopwatch.reset();
          _stopwatch.start();
          final List<ImageLabel> labels = await _imageLabeler.processImage(mlkitImage);
          _stopwatch.stop();
          _log.fine('Image labeling took: ${_stopwatch.elapsedMilliseconds} ms');

          // Check if we saw a hotdog
          if (labels.any((label) => label.label == 'Hot dog')) {
            _isHotdog = true;
            var hd = labels.firstWhere((label) => label.label == 'Hot dog');
            _log.fine('Hotdog! ${hd.confidence}');
          }
          else {
            _isHotdog = false;
            _log.fine('Not hotdog!');
          }

          // TODO for the moment just slow down the rate of photos
          //await Future.delayed(const Duration(seconds: 5));
          currentState = ApplicationState.ready;
          if (mounted) setState(() {});

        } catch (e, stacktrace) {
          _log.severe('Error converting bytes to image: $e $stacktrace');
        }

      } catch (e) {
        _log.severe('Error executing application: $e');
      }
    }
  }

  /// cancel the current photo
  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hotdog / Not Hotdog',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Hotdog / Not Hotdog'),
          actions: [getBatteryWidget()]
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ElevatedButton(onPressed: run, child: const Text('Run!')),
                  if (_isHotdog != null) Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform(
                        alignment: Alignment.center,
                        // images are rotated 90 degrees clockwise from the Frame
                        // so reverse that for display
                        transform: Matrix4.rotationZ(-pi*0.0),//FIXME Matrix4.rotationZ(-pi*0.5),
                        child: _image,
                      ),
                      Container(
                        width: double.infinity,
                        height: 150,
                        color: Colors.white54,
                      ),
                      if (_isHotdog != null)
                      Row(children: [
                        const Spacer(),
                        Image.asset('assets/sprites/text_${_isHotdog! ? '' : 'not'}hotdog.png', width: 200),
                        const Spacer(),
                        Image.asset('assets/sprites/${_isHotdog! ? '' : 'not'}hotdog.png', width: 100,),
                        const Spacer(),
                      ],)
                    ],
                  ),
                ],
              )
            ),
          ],
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.camera_alt), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}
