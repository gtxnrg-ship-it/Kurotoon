# Shop account and administrator security requirements

## Designated administrator
The intended administrator email supplied for Kurotoon is `gtxnrg@gmail.com`. This is a configuration value to verify during deployment, not proof of identity. Do not grant privileges from a client-side email string or from a local setting.

## Required sign-in behavior
- Use a trusted identity provider (Google Sign-In is the preferred Android-first option).
- Verify the provider's ID token on a trusted backend.
- Assign the administrator role only after the backend compares the verified identity against a server-side allowlist.
- Never ship admin credentials, signing secrets, service-account keys, or privileged tokens in the Flutter app.
- Keep collection ownership, balances, purchases, and achievement grants associated with the authenticated user ID in server-side storage.
- Users should be able to sign out, recover their account through the identity provider, and restore their collection on another device.
- The administrator can view/unlock the full catalog, including Progenitor, Celestial, and Cute Kuro. Every admin grant must be authorized server-side and auditable.

## Legendary reward rules
- **Progenitor**: non-purchasable founding reward or explicit administrator grant.
- **Celestial**: earned by completing the server-validated multi-step collection quest.
- **Cute Kuro**: earned by completing the server-validated secret Kuro achievement sequence.

The current Shop stores balances and ownership in the local app database. That is suitable for a local prototype only; it is not secure account sync, and a modified client can tamper with local values. Do not describe the account system as implemented until a provider, backend authorization, server persistence, and cross-device restoration are wired and tested.

## Release checklist
- [ ] Configure provider credentials in deployment secrets.
- [ ] Verify the Google identity token on the backend.
- [ ] Configure the admin allowlist with the intended verified account.
- [ ] Add server-side collection and wallet persistence.
- [ ] Enforce purchases and legendary unlock conditions on the backend.
- [ ] Test regular-user denial of admin actions and all three legendary grants.
- [ ] Test sign-out, account recovery, and cross-device restoration.
