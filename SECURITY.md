# Security

Terrenos stores land records only on users' phones and shares them directly
between phones, encrypted with a group key (SPEC.md §9.6). Weaknesses in that
design matter, so please report them.

## Reporting a vulnerability

Use GitHub's **private vulnerability reporting** on this repository
("Security" tab → "Report a vulnerability"). Don't open a public issue.

Include what you found, how to reproduce it, and what an attacker could do
with it. You will get a reply within 14 days.

## Scope

- Group keys, QR invites, sync files and backup files (SPEC.md §9)
- The Nearby sync handshake
- Data leaving the phone in any way other than the user's explicit action
