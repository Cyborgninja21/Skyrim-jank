#!/usr/bin/env python3

# GPU FIX: Backup check in case bash script doesn't set environment
import os
if 'CUDA_VISIBLE_DEVICES' not in os.environ:
    print("WARNING: Setting GPU environment from Python")
    os.environ['CUDA_VISIBLE_DEVICES'] = '1'
    os.environ['CUDA_DEVICE_ORDER'] = 'PCI_BUS_ID'

import torch
import torchaudio

# Debug: Confirm GPU selection
print(f"Model download using: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'}")

from zonos.model import Zonos
from zonos.conditioning import make_cond_dict
from zonos.utils import DEFAULT_DEVICE as device

print("Downloading hybrid model...")
model = Zonos.from_pretrained("Zyphra/Zonos-v0.1-hybrid", device=device)
print("Downloading transformer model...")
model = Zonos.from_pretrained("Zyphra/Zonos-v0.1-transformer", device=device)
print("All models downloaded successfully!")