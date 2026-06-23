import os
from flask import Flask
import pg8000.native

app = Flask(__name__)


def get_db_connection():
    """Connect to Cloud SQL via Unix socket (Cloud SQL Auth Proxy)."""
    db_user = os.environ.get("DB_USER", "lab08user")
    db_pass = os.environ.get("DB_PASS", "lab08password")
    db_name = os.environ.get("DB_NAME", "lab08db")
    db_socket = os.environ.get("DB_SOCKET", "/cloudsql")
    instance_connection = os.environ.get("INSTANCE_CONNECTION_NAME", "")

    unix_socket = f"{db_socket}/{instance_connection}"

    conn = pg8000.native.Connection(
        user=db_user,
        password=db_pass,
        database=db_name,
        unix_sock=unix_socket
    )
    return conn


@app.route("/")
def index():
    try:
        conn = get_db_connection()
        result = conn.run("SELECT version(), current_database(), current_user")
        conn.close()
        pg_version, db_name, db_user = result[0]
        return f"""
<html><body>
<h1>Cloud Run + Cloud SQL</h1>
<p><strong>Connected to:</strong> {db_name}</p>
<p><strong>User:</strong> {db_user}</p>
<p><strong>PostgreSQL:</strong> {pg_version[:50]}...</p>
<p><strong>Status:</strong> Connected successfully</p>
</body></html>
"""
    except Exception as e:
        return f"<html><body><h1>Connection failed</h1><p>{e}</p></body></html>", 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
