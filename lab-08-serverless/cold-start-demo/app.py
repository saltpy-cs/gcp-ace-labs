import os
import time
from flask import Flask

app = Flask(__name__)
_initialised = False
REVISION = os.environ.get("K_REVISION", "unknown")


@app.route("/")
def hello():
    global _initialised
    if not _initialised:
        print("First request: performing cold start initialisation...", flush=True)
        time.sleep(5)
        _initialised = True
        print("Initialisation complete.", flush=True)
    return f"<h1>Hello from Cloud Run! (revision: {REVISION})</h1>\n"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
