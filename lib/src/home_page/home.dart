import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:tflite/tflite.dart';

import '../../constants/constants.dart';
import '../../services/classify.dart';
import '../../services/disease_provider.dart';
import '../../services/hive_database.dart';
import '../suggestions_page/suggestions.dart';
import 'components/greeting.dart';
import 'components/history.dart';
import 'components/titlesection.dart';
import 'models/disease_model.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  static const routeName = '/';

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
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
        // Check if a capture is in progress
        if (!cameraController!.value.isTakingPicture) {
          // Add these lines to lock focus and exposure before taking a picture
          await cameraController!.setFocusMode(FocusMode.locked);
          await cameraController!.setExposureMode(ExposureMode.locked);

          XFile image = await cameraController!.takePicture();

          // After taking a picture, unlock focus and exposure
          await cameraController!.setFocusMode(FocusMode.auto);
          await cameraController!.setExposureMode(ExposureMode.auto);

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
        } else {
          // Wait for the previous capture to complete and then try again
          await Future.delayed(Duration(milliseconds: 100));
          classifyFrame();
        }
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
    final _diseaseService = Provider.of<DiseaseService>(context);

    // Hive service
    HiveService _hiveService = HiveService();

    // Data
    Size size = MediaQuery.of(context).size;
    final Classifier classifier = Classifier();
    late Disease _disease;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SpeedDial(
        icon: Icons.camera_alt,
        spacing: 10,
        children: [
          SpeedDialChild(
            child: const FaIcon(
              FontAwesomeIcons.file,
              color: kWhite,
            ),
            label: "Choose image",
            backgroundColor: kMain,
            onTap: () async {
              late double _confidence;
              await classifier.getDisease(ImageSource.gallery).then((value) {
                _disease = Disease(
                    name: value![0]["label"],
                    imagePath: classifier.imageFile.path);

                _confidence = value[0]['confidence'];
              });
              // Check confidence
              if (_confidence > 0.8) {
                // Set disease for Disease Service
                _diseaseService.setDiseaseValue(_disease);

                // Save disease
                _hiveService.addDisease(_disease);

                Navigator.restorablePushNamed(
                  context,
                  Suggestions.routeName,
                );
              } else {
                // Display unsure message

              }
            },
          ),
          SpeedDialChild(
            child: const FaIcon(
              FontAwesomeIcons.camera,
              color: kWhite,
            ),
            label: "Take photo",
            backgroundColor: kMain,
            onTap: () async {
              late double _confidence;

              await classifier.getDisease(ImageSource.camera).then((value) {
                _disease = Disease(
                    name: value![0]["label"],
                    imagePath: classifier.imageFile.path);

                _confidence = value[0]['confidence'];
              });

              // Check confidence
              if (_confidence > 0.8) {
                // Set disease for Disease Service
                _diseaseService.setDiseaseValue(_disease);

                // Save disease
                _hiveService.addDisease(_disease);

                Navigator.restorablePushNamed(
                  context,
                  Suggestions.routeName,
                );
              } else {
                // Display unsure message

              }
            },
          ),
          SpeedDialChild(
            // This is the new camera access button
            child: Icon(
              Icons.camera_alt,
              color: Colors.white,
            ),
            label: "Camera Access",
            backgroundColor: Colors.blue,
            onTap: () {
              setState(() {
                isDetecting = !isDetecting;
              });
              if (isDetecting) {
                classifyFrame();
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
              image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: CustomScrollView(
          slivers: [
            GreetingSection(size.height * 0.2),
            // TitleSection('Instructions', size.height * 0.066),
            // InstructionsSection(size),
            TitleSection('Your History', size.height * 0.066),
            HistorySection(size, context, _diseaseService)
          ],
        ),
      ),
    );
  }
}
