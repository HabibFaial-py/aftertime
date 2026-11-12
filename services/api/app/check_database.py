"""Local operator command: python -m app.check_database. No API route."""

import sys

from app.config import DatabaseConfigurationError
from app.database import DatabaseRepository, DatabaseUnavailableError


def main() -> int:
    try:
        DatabaseRepository().check_connection()
    except DatabaseConfigurationError:
        print("Database configuration is missing or invalid.", file=sys.stderr)
        return 2
    except DatabaseUnavailableError:
        print("Database connectivity check failed.", file=sys.stderr)
        return 1
    print("Database connectivity check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
