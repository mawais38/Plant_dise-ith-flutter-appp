import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:tflite/tflite.dart';

class HandGestureRecognitionWidget extends StatefulWidget {
  @override
  _HandGestureRecognitionWidgetState createState() =>
      _HandGestureRecognitionWidgetState();
}

class _HandGestureRecognitionWidgetState
    extends State<HandGestureRecognitionWidget> {
  CameraController? cameraController;
  List<CameraDescription> cameras = [];
  bool isDetecting = false;
  String? prediction;

  @override
  void initState() {
    super.initState();
    initializeCamera();
    loadModel();
  }

  Future<void> initializeCamera() async {
    try {
      cameras = await availableCameras();
      cameraController = CameraController(cameras[0], ResolutionPreset.medium);
      await cameraController!.initialize();
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> loadModel() async {
    try {
      await Tflite.loadModel(
        model: "assets/model/model_unquant.tflite",
        labels: "assets/model/labels.txt",
        numThreads: 1,
      );
    } catch (e) {
      print('Error loading model: $e');
    }
  }

  Future<void> classifyFrame() async {
    if (!isDetecting) {
      return;
    }

    if (cameraController != null && cameraController!.value.isInitialized) {
      try {
        XFile image = await cameraController!.takePicture();

        var output = await Tflite.runModelOnImage(
          path: image.path,
          imageMean: 0.0,
          imageStd: 255.0,
          numResults: 1,
          threshold: 0.2,
          asynch: true,
        );

        if (output != null && output.isNotEmpty) {
          setState(() {
            prediction = output[0]['label'];
          });
        }

        classifyFrame(); // Continue to classify frames
      } catch (e) {
        print('Error classifying frame: $e');
      }
    }
  }

  @override
  void dispose() {
    if (cameraController != null) {
      cameraController!.dispose();
    }
    Tflite.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return CircularProgressIndicator(); // Show loading indicator while initializing the camera
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: <Widget>[
        CameraPreview(cameraController!),
        Container(
          alignment: Alignment.bottomCenter,
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Prediction: $prediction',
            style: TextStyle(
              fontSize: 24.0,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              isDetecting = !isDetecting;
            });
            if (isDetecting) {
              classifyFrame();
            }
          },
          child: Container(
            alignment: Alignment.bottomCenter,
            padding: EdgeInsets.all(16.0),
            child: Text(
              isDetecting ? 'Stop Detection' : 'Start Detection',
              style: TextStyle(
                fontSize: 24.0,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
