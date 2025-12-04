# CoreML Model Converter Guide

## 📦 Konvertierung von AI-Modellen für iOS

Dieses Dokument erklärt, wie Sie Deep Learning Modelle (PyTorch, TensorFlow, ONNX) für die Verwendung in Ihrer iOS-App konvertieren.

---

## 🎯 Übersicht

### Unterstützte Workflows:

```
PyTorch → CoreML (direkt)
TensorFlow → CoreML (über TF Lite)
ONNX → CoreML (empfohlen für Flexibilität)
Hugging Face → CoreML (für Transformers)
```

---

## 🔧 Option 1: PyTorch → CoreML (mesh-ai-assist)

### Voraussetzungen:

```bash
pip install coremltools torch torchvision
```

### Konvertierungs-Skript:

```python
#!/usr/bin/env python3
"""
Convert mesh-ai-assist Neural Mesh Simplification model to CoreML
"""

import torch
import coremltools as ct
from neural_mesh_simplification import NeuralMeshSimplifier

# Schritt 1: Laden des PyTorch Modells
print("Loading PyTorch model...")
simplifier = NeuralMeshSimplifier()

# Wenn Sie ein trainiertes Modell haben:
# model.load_state_dict(torch.load('checkpoint.pth'))
model = simplifier.model  # Annahme: Modell ist zugänglich
model.eval()

# Schritt 2: Erstellen eines Beispiel-Inputs
# Für mesh-ai-assist: (batch, num_vertices, 3)
batch_size = 1
num_vertices = 1024  # Max vertices für iOS
example_input = torch.rand(batch_size, num_vertices, 3)

print(f"Example input shape: {example_input.shape}")

# Schritt 3: Tracen des Modells
print("Tracing model...")
with torch.no_grad():
    traced_model = torch.jit.trace(model, example_input)

# Schritt 4: Konvertierung zu CoreML
print("Converting to CoreML...")
coreml_model = ct.convert(
    traced_model,
    inputs=[ct.TensorType(
        name="vertex_positions",
        shape=(batch_size, num_vertices, 3),
        dtype=float
    )],
    outputs=[ct.TensorType(
        name="simplified_vertices",
        dtype=float
    )],
    compute_units=ct.ComputeUnit.ALL,  # CPU + GPU + Neural Engine
    minimum_deployment_target=ct.target.iOS17
)

# Schritt 5: Metadata hinzufügen
coreml_model.author = "Your Name"
coreml_model.license = "MIT"
coreml_model.short_description = "Neural Mesh Simplification for iOS"
coreml_model.version = "1.0"

# Schritt 6: Speichern
output_path = "MeshSimplificationModel.mlpackage"
coreml_model.save(output_path)
print(f"✅ Model saved to {output_path}")

# Schritt 7: Testen
print("\nTesting CoreML model...")
test_input = {"vertex_positions": example_input.numpy()}
prediction = coreml_model.predict(test_input)
print(f"Output shape: {prediction['simplified_vertices'].shape}")
print("✅ Conversion successful!")
```

### Model für iOS optimieren:

```python
# Quantisierung für kleinere Dateigröße
import coremltools.optimize.coreml as cto

op_config = cto.OpLinearQuantizerConfig(mode="linear_symmetric")
config = cto.OptimizationConfig(global_config=op_config)

compressed_model = cto.linear_quantize_weights(coreml_model, config=config)
compressed_model.save("MeshSimplificationModel_Quantized.mlpackage")
```

---

## 🔧 Option 2: ONNX → CoreML (Flexibler Workflow)

### Für beliebige Frameworks:

```bash
pip install onnx onnx-coreml
```

### PyTorch → ONNX → CoreML:

```python
import torch
import onnx
from onnx_coreml import convert

# 1. PyTorch → ONNX
torch.onnx.export(
    model,
    example_input,
    "mesh_model.onnx",
    input_names=["vertices"],
    output_names=["simplified"],
    dynamic_axes={
        "vertices": {0: "batch", 1: "num_vertices"},
        "simplified": {0: "batch", 1: "num_vertices"}
    }
)

# 2. ONNX → CoreML
onnx_model = onnx.load("mesh_model.onnx")
coreml_model = convert(
    onnx_model,
    minimum_ios_deployment_target='17'
)
coreml_model.save("MeshModel.mlmodel")
```

---

## 🎮 Option 3: Metal Performance Shaders ML (Alternative)

Für kleinere, Custom-Netzwerke können Sie direkt Metal Performance Shaders verwenden:

```swift
import MetalPerformanceShadersGraph

// Graph-basierte Neural Networks direkt in Swift
let graph = MPSGraph()

// Beispiel: Einfaches Netzwerk
let input = graph.placeholder(shape: [1, 1024, 3], dataType: .float32, name: "input")
let weights = graph.variable(with: weightsTensor, name: "weights")
let matmul = graph.matrixMultiplication(primary: input, secondary: weights, name: "matmul")
let output = graph.reLU(with: matmul, name: "output")
```

---

## 📱 Integration in Xcode

### 1. Model zu Xcode hinzufügen:

1. `.mlpackage` oder `.mlmodel` in Xcode Project ziehen
2. Xcode generiert automatisch Swift-Interface
3. Im Target unter "Copy Bundle Resources" sicherstellen

### 2. Swift Code:

```swift
import CoreML

class MeshAIProcessor {
    private var model: MeshSimplificationModel?

    func loadModel() async throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine  // Nutze Neural Engine
        config.allowLowPrecisionAccumulationOnGPU = true

        model = try await MeshSimplificationModel.load(configuration: config)
        print("✅ Model loaded on Neural Engine")
    }

    func simplify(vertices: [SIMD3<Float>]) async throws -> [SIMD3<Float>] {
        guard let model = model else {
            throw ModelError.notLoaded
        }

        // Prepare input
        let inputArray = try MLMultiArray(shape: [1, 1024, 3], dataType: .float32)
        for i in 0..<min(vertices.count, 1024) {
            inputArray[i * 3 + 0] = NSNumber(value: vertices[i].x)
            inputArray[i * 3 + 1] = NSNumber(value: vertices[i].y)
            inputArray[i * 3 + 2] = NSNumber(value: vertices[i].z)
        }

        // Run inference
        let input = MeshSimplificationModelInput(vertex_positions: inputArray)
        let output = try model.prediction(input: input)

        // Process output
        let simplified = output.simplified_vertices
        // ... convert back to SIMD3<Float>

        return []
    }
}
```

---

## 🚀 Performance-Optimierung

### 1. Model Quantization:

```python
# 16-bit statt 32-bit (kleinere Größe, fast gleiche Genauigkeit)
coreml_model = ct.convert(
    traced_model,
    inputs=[...],
    compute_precision=ct.precision.FLOAT16
)
```

### 2. Neural Engine Optimierung:

```python
# Für Neural Engine optimieren
config = ct.ComputeUnit.ALL  # Automatische Auswahl
# oder explizit:
config = ct.ComputeUnit.NEURAL_ENGINE
```

### 3. Batch Processing:

```swift
// Mehrere Meshes gleichzeitig verarbeiten
let batchSize = 4
let batchInput = try MLMultiArray(shape: [batchSize, 1024, 3], dataType: .float32)
```

---

## 📊 Model-Größen Guidelines

| Modell-Typ | Empfohlene Größe | Kommentar |
|------------|------------------|-----------|
| Simple CNN | < 5 MB | Ideal für Echtzeit |
| Medium Network | 5-20 MB | Gute Balance |
| Large Network | 20-50 MB | Maximale Qualität |
| Transformer | > 50 MB | Nur wenn nötig |

---

## 🧪 Testing & Validation

### Genauigkeit testen:

```python
import numpy as np

# PyTorch Prediction
with torch.no_grad():
    pytorch_output = model(example_input)

# CoreML Prediction
coreml_output = coreml_model.predict({"vertices": example_input.numpy()})

# Vergleichen
diff = np.abs(pytorch_output.numpy() - coreml_output["simplified_vertices"])
print(f"Max difference: {diff.max()}")
print(f"Mean difference: {diff.mean()}")

# Akzeptabel: < 1e-4 für float32, < 1e-2 für float16
```

### Performance testen (iOS):

```swift
import os.signpost

let signposter = OSSignposter()
let signpostID = signposter.makeSignpostID()

let state = signposter.beginInterval("ModelInference", id: signpostID)
let output = try await model.prediction(input: input)
signposter.endInterval("ModelInference", state)
```

---

## 🔗 Hilfreiche Resources

- **Apple CoreML Tools**: https://github.com/apple/coremltools
- **ONNX CoreML**: https://github.com/onnx/onnx-coreml
- **PyTorch Mobile**: https://pytorch.org/mobile/
- **Apple ML Docs**: https://developer.apple.com/machine-learning/
- **Hugging Face CoreML**: https://huggingface.co/docs/transformers/serialization#coreml

---

## 💡 Best Practices

1. **Start Simple**: Testen Sie zuerst mit einfachen Modellen
2. **Profile Early**: Nutzen Sie Instruments für Performance-Analyse
3. **Quantize Smart**: 16-bit ist oft ausreichend für Mesh-Processing
4. **Cache Models**: Laden Sie Modelle nur einmal beim App-Start
5. **Async Processing**: Nutzen Sie async/await für UI-Responsiveness
6. **Error Handling**: Implementieren Sie Fallback auf CPU-Algorithmen

---

## 🎯 Nächste Schritte

1. **Aktuell**: Nutzen Sie die nativen Swift-Algorithmen (QEM, Vertex Clustering)
2. **Phase 2**: Konvertieren Sie mesh-ai-assist Model zu CoreML
3. **Phase 3**: Trainieren Sie Custom Models für Ihre Use-Cases
4. **Phase 4**: Integrieren Sie Transformer-basierte Modelle (MeshAnything)

---

**Fragen?** Konsultieren Sie die Apple Developer Dokumentation oder öffnen Sie ein Issue im mesh-ai-assist Repository.
