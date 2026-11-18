# v5.2.59 — Research Source Adapter

Research now follows a catalog-first identity flow inspired by modern Windows debloat tooling: executable/parent-folder evidence, uninstall registry install-location matching, AppX package identity, WinGet local catalog, then multi-lane web corroboration. GitHub is used as a higher-trust corroboration lane when identity aligns; Reddit is low-trust community context only and never authoritative identity proof. Duplicate service research implementations were removed so the parent-folder-aware implementation is the only active one.

The launcher and startup path are unchanged from the stable baseline.
