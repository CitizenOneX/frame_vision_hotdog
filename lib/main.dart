import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';

import 'package:simple_frame_app/tx/camera_settings.dart';
import 'package:simple_frame_app/image_data_response.dart';
import 'package:image_mlkit_converter/image_mlkit_converter.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/code.dart';

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
    Logger.root.level = Level.INFO;
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
        var takePhoto = TxCameraSettings(msgCode: 0x0d);
        await frame!.sendMessage(takePhoto);

        // synchronously await the image response encoded as a jpeg
        // TODO consider testing to see if there's an image ready or not, otherwise sleep and loop around again
        Uint8List imageData = await imageDataResponse(frame!.dataResponse, 10).first;

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

            // let the Frame know it's a hotdog
            frame!.sendMessage(TxCode(msgCode: 0x0e, value: 1));
          }
          else {
            _isHotdog = false;
            _log.fine('Not hotdog!');

            // let the Frame know it's NOT a hotdog
            frame!.sendMessage(TxCode(msgCode: 0x0e, value: 0));
          }

          // TODO just exit the loop for now, once is enough
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
                  if (_isHotdog != null) Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform(
                        alignment: Alignment.center,
                        // images are rotated 90 degrees clockwise from the Frame
                        // so reverse that for display
                        transform: Matrix4.rotationZ(-pi*0.5),
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
                        Image.asset('assets/sprites/${_isHotdog! ? '21_text_' : '23_text_not'}hotdog.png', width: 200),
                        const Spacer(),
                        Image.asset('assets/sprites/${_isHotdog! ? '20_' : '22_not'}hotdog128.png', width: 100,),
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
