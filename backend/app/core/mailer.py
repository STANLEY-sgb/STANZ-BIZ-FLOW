"""Email delivery boundary.

`log` backend is for development: it records that an email *would* be sent,
without the token-bearing body, and reports `delivered=False` so callers never
claim a message was sent.
"""

import logging
import smtplib
from email.message import EmailMessage

from app.core.config import get_settings

logger = logging.getLogger("bizflow.email")


def send_email(to: str, subject: str, body: str) -> bool:
    settings = get_settings()
    if settings.email_backend == "smtp":
        message = EmailMessage()
        message["From"] = settings.smtp_from
        message["To"] = to
        message["Subject"] = subject
        message.set_content(body)
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as smtp:
            smtp.starttls()
            if settings.smtp_username:
                smtp.login(settings.smtp_username, settings.smtp_password)
            smtp.send_message(message)
        return True
    logger.info("Email not delivered (EMAIL_BACKEND=%s): subject=%r", settings.email_backend, subject)
    return False
