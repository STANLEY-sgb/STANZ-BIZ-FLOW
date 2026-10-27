"""Monetary and quantity helpers.

All money is handled as `Decimal` and stored as NUMERIC. Binary floating point
is never used for financial values.
"""

from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated

from pydantic import Field, PlainSerializer

MONEY_PLACES = Decimal("0.01")
QTY_PLACES = Decimal("0.001")

# NUMERIC(14, 2): up to 999,999,999,999.99 — ample headroom for UGX totals.
MONEY_PRECISION = (14, 2)
QTY_PRECISION = (14, 3)


def money(value: Decimal | int | str) -> Decimal:
    return Decimal(value).quantize(MONEY_PLACES, rounding=ROUND_HALF_UP)


def qty(value: Decimal | int | str) -> Decimal:
    return Decimal(value).quantize(QTY_PLACES, rounding=ROUND_HALF_UP)


# Serialize decimals as strings so clients never lose precision through JSON floats.
MoneyOut = Annotated[Decimal, PlainSerializer(lambda v: str(money(v)), return_type=str)]


def format_qty(value: Decimal) -> str:
    """Render a quantity without trailing zeros and never in exponent form."""
    text = format(qty(value), "f")
    return text.rstrip("0").rstrip(".") if "." in text else text


QtyOut = Annotated[Decimal, PlainSerializer(format_qty, return_type=str)]
MoneyIn = Annotated[Decimal, Field(ge=0, max_digits=14, decimal_places=2)]
QtyIn = Annotated[Decimal, Field(gt=0, max_digits=14, decimal_places=3)]
