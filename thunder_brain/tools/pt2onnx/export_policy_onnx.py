import torch

# 加载 policy（TorchScript）
policy = torch.jit.load("model/model_10400.pt")
policy.eval()

# 构造 dummy 输入
dummy_input = torch.randn(1, 57, dtype=torch.float32)

# 导出为 ONNX
torch.onnx.export(
    policy,
    dummy_input,
    "model/model_10400.onnx",
    export_params=True,
    opset_version=11,
    input_names=["obs"],
    output_names=["action"],
    # dynamic_axes={"obs": {0: "batch_size"}, "action": {0: "batch_size"}},
)

print("Exported policy.onnx successfully.")
