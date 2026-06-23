import functions_framework
import json


@functions_framework.http
def convert_temperature(request):
    """HTTP Cloud Function: converts Celsius to Fahrenheit."""
    request_json = request.get_json(silent=True)
    request_args = request.args

    if request_json and "celsius" in request_json:
        celsius = float(request_json["celsius"])
    elif request_args and "celsius" in request_args:
        celsius = float(request_args["celsius"])
    else:
        return json.dumps({"error": "Missing 'celsius' parameter"}), 400

    fahrenheit = (celsius * 9 / 5) + 32
    return json.dumps({
        "celsius": celsius,
        "fahrenheit": fahrenheit,
        "message": f"{celsius}°C is {fahrenheit}°F"
    })
