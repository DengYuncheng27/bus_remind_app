// Keep the accepted syntax aligned with the API's src/email-address.ts.
// Mailbox existence still requires a successfully received verification code.
bool isValidEmailAddress(String value) {
  final email = value.trim();
  if (email.length > 254) return false;
  final parts = email.split('@');
  if (parts.length != 2) return false;
  final local = parts[0], domain = parts[1];
  if (local.isEmpty ||
      local.length > 64 ||
      !RegExp(r"^[a-zA-Z0-9!#$%&'*+/=?^_`{|}~.-]+$").hasMatch(local)) {
    return false;
  }
  if (local.startsWith('.') || local.endsWith('.') || local.contains('..')) {
    return false;
  }
  final labels = domain.split('.');
  return labels.length >= 2 &&
      labels.every(
        (label) =>
            label.length <= 63 &&
            RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$')
                .hasMatch(label),
      ) &&
      !RegExp(r'^\d+$').hasMatch(labels.last);
}
