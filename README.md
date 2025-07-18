# pg_hashids: Obfuscate Your PostgreSQL IDs 🔐

**pg_hashids** is a PostgreSQL extension that allows you to obfuscate your integer IDs into short, unique, non-sequential hashes. This is a pure PL/pgSQL implementation of the [Hashids](http://hashids.org/) algorithm, designed to be compatible with PostgreSQL Trusted Language Extensions (TLE) for deployment on managed PostgreSQL services like AWS RDS.

## 🚀 Features

- **Obfuscate IDs**: Turn sequential integer IDs into short, unique hashes (e.g., `123` → `MzG`)
- **Custom Salt**: Use a custom salt to make your hashes unique to your application
- **Minimum Length**: Pad hashes to a minimum length for consistency
- **Custom Alphabet**: Define your own character set for generated hashes
- **Pure PL/pgSQL**: No C dependencies - works everywhere PostgreSQL runs
- **TLE Compatible**: Deploy on AWS RDS and other managed PostgreSQL services
- **Backward Compatible**: Includes legacy function aliases from version 1.x

## 🛠️ Installation

You can install pg_hashids using the standard PostgreSQL extension system.

### Prerequisites

- **PostgreSQL Version**: 9.5 or higher (with PL/pgSQL support)
- **For AWS RDS**: PostgreSQL 13.7+, 14.6+, or 15.2+ with pg_tle enabled

### Fresh Installation

```sql
-- Create the extension
CREATE EXTENSION pg_hashids;

-- Verify installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_hashids';
```

### Direct Installation (without CREATE EXTENSION)

If you cannot use `CREATE EXTENSION` in your environment:

```sql
-- Run the direct installation script
\i pg_hashids_direct.sql
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

### Basic Usage

#### Encoding

```sql
-- Basic encoding
SELECT id_encode(123); -- Returns: 'MzG'

-- With a custom salt
SELECT id_encode(123, 'my salt'); -- Returns: 'gz5'

-- With a minimum length (pads the hash if needed)
SELECT id_encode(123, 'my salt', 10); -- Returns: 'qgz53'

-- With a custom alphabet
SELECT id_encode(123, 'my salt', 0, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'); -- Returns: 'YKR'
```

#### Decoding

```sql
-- Basic decoding (returns an array)
SELECT id_decode('MzG'); -- Returns: {123}

-- Decode to a single value
SELECT id_decode_once('MzG'); -- Returns: 123

-- With a custom salt (must match the encoding salt)
SELECT id_decode('gz5', 'my salt'); -- Returns: {123}
SELECT id_decode_once('gz5', 'my salt'); -- Returns: 123
```

### Advanced Examples

```sql
-- Round-trip encoding/decoding
SELECT id_decode_once(id_encode(12345)); -- Returns: 12345

-- Using in a table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email TEXT
);

-- Create a view with obfuscated IDs
CREATE VIEW public_users AS
SELECT 
    id_encode(id, 'your-secret-salt') AS public_id,
    email
FROM users;

-- Query by obfuscated ID
SELECT * FROM users 
WHERE id = id_decode_once('encoded-id-here', 'your-secret-salt');
```

### Legacy Function Support

For backward compatibility with version 1.x:

```sql
-- Legacy encoding functions
SELECT hash_encode(123);
SELECT hash_encode(123, 'salt');
SELECT hash_encode(123, 'salt', 10);

-- Legacy decoding function
SELECT hash_decode('gz5', 'salt', 0);
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

## 🔧 Troubleshooting

### Common Issues

#### "syntax error at or near '$'"
This occurs when the SQL files have incorrect dollar-quoting. Ensure you're using the corrected version where all `AS $` are replaced with `AS $$`.

#### "type 'hashids_config' already exists"
This happens when there are leftover objects from a previous installation attempt. Clean up with:
```sql
DROP TYPE IF EXISTS hashids_config CASCADE;
```

#### "extension 'pg_hashids' does not exist"
- Verify that pg_hashids.control and pg_hashids--2.0.sql are in your PostgreSQL extension directory
- Check with: `pg_config --sharedir` and look in the `extension/` subdirectory
- For AWS RDS, ensure pg_tle is installed first

#### "Hash cannot be empty" or "Invalid hash format"
These are expected errors when:
- Trying to decode an empty string
- Decoding a hash with characters not in the alphabet
- Using mismatched salts between encoding and decoding

### Performance Considerations

- The PL/pgSQL implementation is slower than the original C version but provides broader compatibility
- For high-volume applications, consider caching encoded values
- Custom alphabets with fewer characters will produce longer hashes

### Limitations

- Only supports positive integers (including 0)
- Maximum integer value is PostgreSQL's BIGINT limit (9223372036854775807)
- Minimum length padding may not work for very large minimum lengths
- The algorithm is designed for obfuscation, not cryptographic security

## 📚 API Reference

### Encoding Functions

- `id_encode(bigint) → text`
- `id_encode(bigint, text) → text`
- `id_encode(bigint, text, integer) → text`
- `id_encode(bigint, text, integer, text) → text`

Parameters:
- `bigint`: The number to encode (must be non-negative)
- `text`: Salt (optional, default: empty string)
- `integer`: Minimum hash length (optional, default: 0)
- `text`: Custom alphabet (optional, default: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890')

### Decoding Functions

- `id_decode(text) → bigint[]`
- `id_decode(text, text) → bigint[]`
- `id_decode(text, text, integer) → bigint[]`
- `id_decode(text, text, integer, text) → bigint[]`

- `id_decode_once(text) → bigint`
- `id_decode_once(text, text) → bigint`
- `id_decode_once(text, text, integer) → bigint`
- `id_decode_once(text, text, integer, text) → bigint`

Parameters must match those used for encoding.

### Legacy Functions (v1.x compatibility)

- `hash_encode(bigint) → text`
- `hash_encode(bigint, text) → text`
- `hash_encode(bigint, text, integer) → text`
- `hash_decode(text, text, integer) → bigint`

## 🙏 Credits

This project is a fork of the original [pg_hashids](https://github.com/iCyberon/pg_hashids) by [iCyberon](https://github.com/iCyberon). A big thank you to them for their work! 🎉

Version 2.0 was rewritten in pure PL/pgSQL for TLE compatibility.

## 📝 Version History

### Version 2.0 (Current)
- Complete rewrite in pure PL/pgSQL
- TLE (Trusted Language Extensions) compatibility
- AWS RDS support without C compilation
- Maintains API compatibility with v1.x
- Includes all original functionality

### Version 1.3 and earlier
- Original C implementation
- Required compilation and superuser access
- Not compatible with managed PostgreSQL services

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request.

When contributing:
- Ensure all PL/pgSQL functions use proper dollar-quoting (`$$`)
- Test with both `CREATE EXTENSION` and direct SQL installation methods
- Maintain backward compatibility with existing function signatures
- Update both `pg_hashids--2.0.sql` and `pg_hashids_direct.sql` when making changes

## 📜 License

This project is licensed under the [MIT License](LICENSE).
