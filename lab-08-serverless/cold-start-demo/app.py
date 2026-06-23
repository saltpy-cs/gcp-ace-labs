import os
import time
from flask import Flask

app = Flask(__name__)

print("Initialising application (simulating DB connection pool, model load, etc.)...", flush=True)
time.sleep(5)
print("Ready to serve requests.", flush=True)


@app.route("/")
def hello():
    return "<h1>Hello from Cloud Run!</h1>\n"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
