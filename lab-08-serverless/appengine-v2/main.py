from flask import Flask
import os
import platform

app = Flask(__name__)


@app.route("/")
def index():
    return f"""
<!DOCTYPE html>
<html>
<head><title>Lab 08 - App Engine</title></head>
<body>
<h1>App Engine Standard — Lab 08</h1>
<p>Version: {os.environ.get('VERSION', '1.0')}</p>
<p>Python: {platform.python_version()}</p>
<p>Instance: {os.environ.get('GAE_INSTANCE', 'local')}</p>
<p>Service: {os.environ.get('GAE_SERVICE', 'default')}</p>
</body>
</html>
"""


@app.route("/health")
def health():
    return {"status": "ok", "version": os.environ.get("VERSION", "1.0")}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
