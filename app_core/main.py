from flask import Flask
from flask_cors import CORS


def create_app():
    """
    Factory de la app Flask.
    Se registrarán blueprints y configuración aquí.
    """
    app = Flask(__name__)
    CORS(app)

    # Los blueprints se registrarán más adelante
    try:
        from app_core.presentation.api import api_bp
        app.register_blueprint(api_bp)
    except Exception:
        # Permite iniciar mientras se migra código.
        pass

    return app
