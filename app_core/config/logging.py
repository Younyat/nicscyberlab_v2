import logging
from logging.handlers import RotatingFileHandler


def setup_logging(log_file: str = "app.log") -> logging.Logger:
    """
    Configura logging con handler rotativo y salida a consola.
    Retorna el logger principal.
    """
    logger = logging.getLogger("app_logger")
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)

    handler = RotatingFileHandler(log_file, maxBytes=5 * 1024 * 1024, backupCount=3)
    formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    return logger

