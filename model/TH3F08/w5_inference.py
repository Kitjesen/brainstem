"""Simulation-compatible observation/action adapter; no hardware communication."""
import numpy as np
import onnxruntime as ort

DEFAULT_Q = np.array([-.12,-.93,1.96,.12,.93,-1.96,.12,.93,-1.96,-.12,-.93,1.96,0,0,0,0], dtype=np.float32)
SCALE = np.array([.125,.25,.25]*4, dtype=np.float32)

def observation(angular_velocity_body, projected_gravity_body, command, q, dq, previous_action):
    arrays = [np.asarray(x, dtype=np.float32) for x in
              (angular_velocity_body, projected_gravity_body, command, q, dq, previous_action)]
    if [x.shape for x in arrays] != [(3,), (3,), (4,), (16,), (16,), (16,)]:
        raise ValueError('Expected shapes 3,3,4,16,16,16 in documented joint order')
    if not all(np.isfinite(x).all() for x in arrays):
        raise ValueError('Non-finite observation input')
    omega, gravity, command, q, dq, last = arrays
    relative = q - DEFAULT_Q
    relative[12:] = 0
    terms = [omega, gravity, command, relative, dq, last]
    scales = [.25, 1, 1, 1, .05, 1]
    return np.concatenate([np.clip(x, -100, 100)*s for x,s in zip(terms, scales)]).reshape(1,58)

def targets(action):
    action = np.asarray(action, dtype=np.float32).reshape(-1)
    if action.shape != (16,) or not np.isfinite(action).all():
        raise ValueError('Expected 16 finite actions')
    applied = np.clip(action, -100, 100)
    return DEFAULT_Q[:12] + SCALE*applied[:12], 5*applied[12:]

