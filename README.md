# PaintApp - iPad Animation and Drawing App

A Procreate-like drawing and animation app for iPad with layer support, brush tools, and animation timeline features.

## Features

- **Drawing Tools**: Pen and pencil brushes with adjustable size
- **Eraser**: Full eraser functionality
- **Layers**: Multiple layers with transparency and visibility controls
- **Canvas Selection**: Multiple preset canvas sizes (iPad Pro, iPad Air, 1080p, 4K, Custom)
- **Animation Timeline**: Frame-by-frame animation with play/pause controls
- **Onion Skinning**: See previous frames as a guide with adjustable opacity
- **Gestures**: Two-finger zoom, rotate, and pan
- **Color Picker**: Preset colors and custom color selection
- **Brush Settings**: Adjustable brush size with live preview

## Project Structure

```
PaintApp/
├── PaintApp.swift              # Main app entry point
├── ContentView.swift           # Root view
├── Models/
│   └── CanvasManager.swift     # Core data and state management
└── Views/
    ├── CanvasSizePickerView.swift  # Canvas size selection
    ├── DrawingView.swift           # Main drawing interface
    ├── CanvasView.swift            # PencilKit canvas wrapper
    ├── TopToolbar.swift            # Top toolbar with tools
    ├── LayerPanel.swift            # Layer management panel
    ├── BrushSettingsPanel.swift    # Brush settings panel
    ├── ColorPickerPanel.swift      # Color picker panel
    └── AnimationTimeline.swift     # Animation timeline and controls
```

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later
- iPad with iPadOS 17.0 or later
- Apple Pencil (recommended for best experience)
- Apple Developer Account (for device deployment)

## How to Load to iPad

### Step 1: Set Up Xcode Project

1. Open Xcode
2. Create a new project: File → New → Project
3. Select "App" under iOS tab
4. Configure your project:
   - Product Name: `PaintApp`
   - Team: Select your Apple Developer team
   - Organization Identifier: Your unique identifier (e.g., `com.yourname`)
   - Interface: SwiftUI
   - Language: Swift
   - Storage: None
5. Save the project to your desired location

### Step 2: Add Project Files

1. In Xcode, delete the default `ContentView.swift` file
2. Copy all the Swift files from this project into your Xcode project:
   - `PaintApp.swift`
   - `ContentView.swift`
   - `Models/CanvasManager.swift`
   - `Views/CanvasSizePickerView.swift`
   - `Views/DrawingView.swift`
   - `Views/CanvasView.swift`
   - `Views/TopToolbar.swift`
   - `Views/LayerPanel.swift`
   - `Views/BrushSettingsPanel.swift`
   - `Views/ColorPickerPanel.swift`
   - `Views/AnimationTimeline.swift`

3. Create the folder structure in Xcode:
   - Right-click on project → New Group → Name it "Models"
   - Right-click on project → New Group → Name it "Views"
   - Move files into their respective groups

### Step 3: Configure Project Settings

1. Select your project in the navigator
2. Under "Signing & Capabilities":
   - Ensure your team is selected
   - Enable "Automatically manage signing"
3. Under "General":
   - Deployment Target: Set to iOS 17.0 or later
   - Devices: Select "iPad"

### Step 4: Add Required Frameworks

1. Select your project target
2. Go to "Build Phases" → "Link Binary With Libraries"
3. Click "+" and add:
   - `PencilKit.framework`
   - `SwiftUI.framework` (should be included by default)

### Step 5: Configure Info.plist

1. Open `Info.plist`
2. Add the following key-value pairs if not present:
   - `UIRequiredDeviceCapabilities` → Array → Add `armv7`
   - `UISupportedInterfaceOrientations` → Array → Add:
     - `UIInterfaceOrientationPortrait`
     - `UIInterfaceOrientationLandscapeLeft`
     - `UIInterfaceOrientationLandscapeRight`

### Step 6: Connect Your iPad

1. Connect your iPad to your Mac using USB
2. On your iPad:
   - Go to Settings → General → VPN & Device Management
   - Trust your development computer if prompted
3. In Xcode, select your iPad from the device dropdown menu (top toolbar)

### Step 7: Build and Run

1. Press `Cmd + R` or click the Play button in Xcode
2. Xcode will build the project and install it on your iPad
3. The app will launch automatically
4. Grant any permissions if prompted

### Step 8: Trust the Developer (First Time Only)

If you see an "Untrusted Developer" message on your iPad:
1. Go to Settings → General → VPN & Device Management
2. Find your developer profile
3. Tap "Trust [Your Name]"
4. Confirm by tapping "Trust"

## Alternative: TestFlight Deployment

For easier distribution without connecting via USB:

1. Build the app for distribution: Product → Archive
2. When archive completes, click "Distribute App"
3. Select "TestFlight & App Store"
4. Follow the prompts to upload to App Store Connect
5. In App Store Connect, add testers and distribute via TestFlight

## Usage Guide

### Creating a Canvas
1. Launch the app
2. Select a canvas size from the presets or enter custom dimensions
3. Tap "Create Canvas"

### Drawing
1. Select a tool from the top toolbar (Pen, Pencil, or Eraser)
2. Adjust brush size using the brush settings panel
3. Choose colors from the color picker
4. Draw on the canvas with your Apple Pencil or finger

### Layers
1. Tap the layers icon (square stack) in the top toolbar
2. Add new layers with the "+" button
3. Adjust layer opacity with the slider
4. Toggle layer visibility with the eye icon
5. Tap a layer to select it for editing
6. Swipe left on a layer to delete it

### Animation
1. Use the timeline at the bottom to manage frames
2. Tap "+" to add a new frame
3. Use the duplicate button to copy the current frame
4. Navigate frames with previous/next buttons
5. Press play to preview your animation
6. Enable onion skinning to see previous frames as a guide

### Canvas Navigation
- **Pinch**: Zoom in/out
- **Two-finger rotate**: Rotate canvas
- **Two-finger drag**: Pan the canvas

## Troubleshooting

**Build Errors**
- Ensure all frameworks are properly linked
- Check that your deployment target is iOS 17.0+
- Verify your signing certificate is valid

**App Crashes on Launch**
- Check that PencilKit is properly linked
- Verify your iPad is running iPadOS 17.0 or later
- Check the console logs in Xcode for specific errors

**Drawing Not Working**
- Ensure you've selected a layer
- Check that the layer is visible (eye icon)
- Verify you have a tool selected (not just the color picker)

**Animation Issues**
- Make sure you have added frames
- Check that onion skinning is enabled if you want to see previous frames
- Verify you're on the correct frame index

## Future Enhancements

- Screen streaming from Windows PC as a layer
- More brush types and custom brushes
- Export to GIF, MP4, or image sequences
- Undo/Redo functionality
- Layer blending modes
- More canvas size presets
- Pressure sensitivity customization
- Apple Pencil double-tap shortcuts

## License

This project is provided as-is for educational and personal use.
