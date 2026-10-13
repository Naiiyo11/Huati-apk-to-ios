import base64
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[2] / '.venv/Lib/site-packages'))
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

clear = b'{"fixture":1}'
pad = 16 - len(clear) % 16
cipher = Cipher(algorithms.AES(b'A7fK92LmXyQw8vRp'), modes.CBC(bytes(16))).encryptor()
encrypted = cipher.update(clear + bytes([pad]) * pad) + cipher.finalize()
assert base64.b64encode(encrypted).decode() == 'BGu00rSpvgFKuj16y9KktQ=='
print('Independent Python AES fixture verified.')
