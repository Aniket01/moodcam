# Moodcam

**Moodcam** is a powerful, offline-first Flutter application designed for real-time facial emotion recognition and stress/fatigue analysis. By entirely running on-device inference, Moodcam protects user privacy while delivering high frame rates and maintaining seamless performance in any lighting condition.

## Key Features

*   **100% Offline Inference:** All Machine Learning runs locally on your device. No images are ever sent to a server.
*   **Real-Time Emotion Recognition:** Detects up to 7 basic emotions (Happy, Sad, Angry, Surprised, Fearful, Disgusted, Neutral) continuously.
*   **Stress & Fatigue Analysis:** Computes a personalized, dynamic stress score based on advanced physiological markers (negative emotion persistence, blinking, PERCLOS, yawning, and squinting).
*   **Background Processing Engine:** Utilizes Dart Isolates to run intensive TFLite models completely off the main UI thread, guaranteeing zero jank and a smooth 60fps UI.
*   **Adaptive Environment :** Adaptive screen flash to maintain analysis accuracy in low-light environments.

## How it Works: The Recognition Pipeline

Moodcam uses a highly-optimized multi-stage pipeline combining ML Kit and a fine-tuned YOLOv11 cls model trained on [FER2025 dataset](https://www.kaggle.com/datasets/shaikhborhanuddin/fer-25).

1.  **Camera Feed (`CameraService`)**: Captures real-time frames from the front-facing camera in YUV420 format(Android standard).
2.  **Face Mesh Detection (`Google ML Kit`)**: 
    *   The `FacePipelineProcessor` passes frames to ML Kit to extract a high-fidelity 468-point face mesh.
    *   10 iris tracking points synthesized to increase accuracy to 478 points to feed into Blendshape model to derive 52 blendshapes that point to facial muscle activations.
3.  **Background Inference (Dart Isolate)**: 
    *   To prevent UI stutter, the heavy lifting occurs in a background thread (Isolate).
    *   The face is cropped and converted to RGB on the fly.
    *   Luminance is calculated to detect low-light environment
    *   YOLOv11 image classification model trained on latest dataset analyzes the face to generate probabilities for 7 core emotions.
4.  **Smart Selfie Flash (Low Light Mode)**: Automatic screen brightness and flash adjustments based on environment luminosity to maintain continuous facial tracking.
5.  **Advanced Metrics & Stress Score (`FaceAnalysisEngine`)**:
    *   Calculates geometric facial features: **EAR** (Eye Aspect Ratio) and **MAR** (Mouth Aspect Ratio).
    *   Maintains a 6-second window to calibrate a dynamic rolling baseline for the user.
    *   Calculates a final **Stress Score** (0-100%) by weighting markers like sustained negative emotion, eye tension (squinting), PERCLOS (drowsiness), and yawn spikes.
6.  **UI & Visualization (`CameraFERScreen`)**: Receives the calculated data and renders it beautifully. Displays the current FPS, the recognized emotion (with emojis and color accents), and a progress bar representing the real-time stress score.

## Architecture

Moodcam embraces a **Feature-First** architecture, ensuring modularity and scalability:

*   **`lib/features/emotion_recognition/data`**: Contains the camera service, Isolate management, and the core analytics engine.
*   **`lib/features/emotion_recognition/domain`**: Contains the pure data models.
*   **`lib/features/emotion_recognition/presentation`**: Widgets, State Management and Views.
*   **`lib/core/constants`**: Houses mathematical constants, specifically facial landmark indices for EAR and MAR calculations.

## Future Roadmap

*   **Improve Stress monitoring** Currently, the timeframe for calibrating and the rolling window of 6 seconds is not enough for accurate stress monitoring. For better reading, historical data needs to be maintained. I intend to soon add persistent storage (of course offline only) to get more reliable analytics with usage.
*   **Historical Timeline:** A dashboard logging daily emotional trends and stress peaks.
