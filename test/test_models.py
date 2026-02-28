import sys
import json
try:
    import tensorflow as tf
except ImportError:
    print(json.dumps({"error": "tensorflow not installed"}))
    sys.exit(0)

def get_details(model_path):
    interpreter = tf.lite.Interpreter(model_path=model_path)
    # interpreter.allocate_tensors()
    inputs = interpreter.get_input_details()
    outputs = interpreter.get_output_details()
    
    in_details = [{"name": i.get("name", ""), "shape": getattr(i.get("shape"), 'tolist', lambda: i.get("shape"))(), "dtype": str(i.get("dtype"))} for i in inputs]
    out_details = [{"name": o.get("name", ""), "shape": getattr(o.get("shape"), 'tolist', lambda: o.get("shape"))(), "dtype": str(o.get("dtype"))} for o in outputs]
    
    return {"inputs": in_details, "outputs": out_details}

try:
    blaze = get_details('assets/models/blazeFace.tflite')
    mesh = get_details('assets/models/faceMesh.tflite')
    blend = get_details('assets/models/blendShapes.tflite')
    print(json.dumps({"blazeFace": blaze, "faceMesh": mesh, "blendShapes": blend}, indent=2))
except Exception as e:
    print(json.dumps({"error": str(e)}))
