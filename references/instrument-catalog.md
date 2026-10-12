# Instrument catalog

`plf-cli instrument-list --root <root> --out <new.json>` reads the currently
loaded QuoteDataCenter metadata through EJClient IPC.

The successful `data` payload uses schema `plf-instrument-catalog/1`:

```json
{
  "schema": "plf-instrument-catalog/1",
  "count": 2,
  "instruments": [
    {"asset_type":"future","name":"苹果","key":"ZCE AP"},
    {"asset_type":"stock","name":"贵州茅台","key":"SSE SHA 600519"}
  ]
}
```

- A future row is deliberately breed-level HYXX data. Append `IDX` for an
  index and `MI` for a main-continuous contract.
- A Chinese future name followed by a month resolves to a dated contract.
  `ZCE` accepts either three or four digits: `苹果611` becomes `ZCE AP 611`,
  while `苹果2610` becomes `ZCE AP 610`. Other exchanges require four digits,
  for example `塑料2611` becomes `DCE L 2611`. Never invent a month.
- A stock row uses the complete QDC `ContractID`. Stock backtests accept only
  that complete value, such as `SSE SHA 600519`; never emit or retry a legacy
  quote/display code such as `600519.SH`.
- The Skill helper caches the list once per local calendar day and installation
  root in `usr/instrument-catalog.json`.
- `references/contracts.seed.json` may map a futures alias to a catalog row,
  but it never overrides the exchange or commodity key returned by the catalog.
- A two-part futures key such as `ZCE AP` is not runnable and returns
  `need_contract`; ask the user for index, main-continuous, or a dated contract.
- `Resolve` only returns a usable key when the match is unique. Ambiguous and
  missing names must be returned to the user instead of guessed.
