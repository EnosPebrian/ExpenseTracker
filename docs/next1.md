Continue refining Pilgrim Tracker transaction forms.

The new Quick Add modal is visually much better and should remain clean.

However, some fields were removed too aggressively.

The correct design principle:

Quick Add = fast daily entry.
Edit Transaction = complete transaction management.

Do not remove data capability. Only separate complexity between surfaces.

---

Quick Add modal:

Keep the clean prototype design:

- Centered compact modal
- Amount
- Account
- Category
- Description
- Save transaction button

However add an expandable advanced option.

Add:

"More options"

or

"Advanced"

at the bottom.

When collapsed:
Show only:

Amount
Account
Category
Description

When expanded:
Show:

Project
Date
Time

For applicable transaction types:

Expense:

- Project
- Date
- Time

Income:

- Project
- Date
- Time
- Tithe preview (future)

Transfer:

- Source account
- Destination account
- Project
- Date
- Time

Asset conversion:

- Source asset
- Destination asset
- Quantity
- Unit
- Unit price
- Fee treatment
- Project
- Date
- Time

---

Edit Transaction:

Keep full functionality.

The edit form should continue showing:

Expense:

- Amount
- Account
- Category
- Project
- Description
- Date
- Time

Income:

- Amount
- Account
- Category
- Project
- Description
- Date
- Time

Transfer:

- Source account
- Destination account
- Project
- Date
- Time

Asset conversion:

- Source asset/account
- Destination asset/account
- Project
- Quantity
- Unit
- Unit price
- Fee treatment
- Description
- Date
- Time

---

Important UX principle:

Do not make users choose between simplicity and capability.

Quick Add should feel like:
Apple Wallet / modern finance app.

Edit should feel like:
professional accounting software.

The underlying transaction model already supports these fields, so only the presentation layer should change.

Preserve:

- TransactionController
- UseCases
- Repository
- Database schema
- UUID
- Versioning
- Sync metadata

After changes:

flutter analyze

flutter test
