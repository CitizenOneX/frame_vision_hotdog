import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:simple_frame_app/frame_vision_app.dart';

import 'package:image_mlkit_converter/image_mlkit_converter.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/code.dart';
import 'package:simple_frame_app/tx/plain_text.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState, FrameVisionAppState {
  // main state of photo request/processing on/off
  bool _processing = false;

  // the image to show
  Image? _image;
  bool? _isHotdog;

  late final ImageLabeler _imageLabeler;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });

    // don't have FrameVisionApp automatically decode/rotate/encode the Frame images, we can pass them to ML Kit rotated
    upright = false;
  }

  @override
  void initState() {
    super.initState();

    // We have a 30% threshold for hotdogs so we exclude burgers etc
    final ImageLabelerOptions options = ImageLabelerOptions(confidenceThreshold: 0.30);
    _imageLabeler = ImageLabeler(options: options);

    // if possible, connect right away and load files on Frame
    // note: camera app wouldn't necessarily run on start
    tryScanAndConnectAndStart(andRun: true);
  }

  @override
  void dispose() {
    // clean up the labeler
    _imageLabeler.close();

    super.dispose();
  }

    @override
  Future<void> onRun() async {
    // initial message to display when running
    await frame!.sendMessage(
      TxPlainText(
        msgCode: 0x0a,
        text: '2-Tap: take photo'
      )
    );
  }

  @override
  Future<void> onCancel() async {
    // no app-specific cleanup required here
  }

  @override
  Future<void> onTap(int taps) async {
    switch (taps) {
      case 2:
        // check if there's processing in progress already and drop the request if so
        if (!_processing) {
          _processing = true;
          // synchronously call the capture and processing of the photo
          await capture().then(process);
        }
        break;
      default:
    }
  }

  /// The vision pipeline to run when a photo is captured
  /// Which in this case is just displaying
  FutureOr<void> process((Uint8List, ImageMetadata) photo) async {
    var imageData = photo.$1;

    img.Image im = img.decodeJpg(imageData)!;
    // Frame images are rotated 90 degrees clockwise so let ML Kit know
    InputImage mlkitImage = ImageMlkitConverter.imageToMlkitInputImage(im, InputImageRotation.rotation90deg);
    final List<ImageLabel> labels = await _imageLabeler.processImage(mlkitImage);

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

    setState(() {
      _image = Image.memory(imageData, gaplessPlayback: true,);
    });

    _processing = false;
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
