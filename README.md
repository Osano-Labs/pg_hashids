# pg_hashids: Obfuscate Your PostgreSQL IDs  obfuscate 🆔

**pg_hashids** is a PostgreSQL extension that allows you to obfuscate your integer IDs into YouTube-style hashes. This is a PL/pgSQL implementation of the [Hashids](http://hashids.org/) algorithm, designed to be compatible with PostgreSQL Trusted Language Extensions (TLE) on platforms like AWS RDS.

## 🚀 Features

- **Obfuscate IDs**: Turn `123` into `jR` and back again.
- **Custom Salt**: Use a custom salt to make your hashes unique.
- **Minimum Length**: Specify a minimum length for your hashes.
- **Custom Alphabet**: Define a custom alphabet for your hashes.
- **TLE Compatible**: Deploy on AWS RDS and other managed PostgreSQL services without needing C compilers.

## 🛠️ Installation

You can install pg_hashids using the standard PostgreSQL extension system.

### Fresh Installation

```sql
-- Create the extension
CREATE EXTENSION pg_hashids VERSION '2.0';

-- Verify installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_hashids';
```

### Upgrading from C Version

If you have the older C-based version of pg_hashids, you can upgrade to the TLE-compatible version:

```sql
-- Upgrade from version 1.3 to 2.0
ALTER EXTENSION pg_hashids UPDATE TO '2.0';

-- Verify upgrade
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_hashids';
```

## ⚙️ Usage

Using pg_hashids is simple and straightforward.

### Encoding

To encode an ID, use the `id_encode` function:

```sql
-- Basic encoding
SELECT id_encode(123); -- jR

-- With a custom salt
SELECT id_encode(123, 'my-salt');

-- With a minimum length
SELECT id_encode(123, 'my-salt', 10);

-- With a custom alphabet
SELECT id_encode(123, 'my-salt', 10, 'abcdefghijklmnopqrstuvwxyz1234567890');
```

### Decoding

To decode a hash, use the `id_decode` function:

```sql
-- Basic decoding
SELECT id_decode('jR'); -- {123}

-- With a custom salt
SELECT id_decode('jR', 'my-salt');
```

## ☁️ AWS RDS TLE Deployment

This version of pg_hashids is designed to work with AWS RDS PostgreSQL using Trusted Language Extensions (TLE).

### Prerequisites

- **PostgreSQL Version**: 13.7+, 14.6+, or 15.2+
- **Permissions**: `rds_superuser` role
- **TLE Extension**: `pg_tle` extension must be installed and enabled.

### Installation Steps

1.  **Verify TLE Availability**:
    ```sql
    SELECT name, default_version, installed_version
    FROM pg_available_extensions
    WHERE name = 'pg_tle';

    CREATE EXTENSION IF NOT EXISTS pg_tle;
    ```
2.  **Install pg_hashids**:
    Follow the installation steps above.

## Troubleshooting 😥

### "extension does not exist"

- Verify that the extension files are in the correct location.
- Check PostgreSQL version compatibility.
- Ensure TLE is properly installed.

### "permission denied"

- Ensure the user has the `rds_superuser` role.

## 🙏 Credits

This project is a fork of the original [pg_hashids](https://github.com/iCyberon/pg_hashids) by [iCyberon](https://github.com/iCyberon). A big thank you to them for their work! 🎉

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## 📜 License

This project is licensed under the [MIT License](LICENSE).
