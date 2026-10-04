-- Expenses paid in US dollars. amount stays in the profile's currency (CAD) and is what budgets and totals add up;
-- an expense paid in US dollars also keeps what was paid (original_amount), converted at the profile's exchange rate
-- when it was entered.

alter table public.expenses
  add column currency        text not null default 'CAD' check (currency in ('CAD', 'USD')),
  add column original_amount numeric(10, 2) check (original_amount > 0),
  add constraint expenses_currency_amount_check check ((currency = 'CAD') = (original_amount is null));
comment on column public.expenses.currency is 'What the expense was paid in. amount is always in the profile''s currency.';
comment on column public.expenses.original_amount is 'What was paid, in currency, when that isn''t CAD. Null for CAD.';

alter table public.profiles
  add column usd_to_cad numeric(6, 4) not null default 1.38 check (usd_to_cad between 0.5 and 3);
comment on column public.profiles.usd_to_cad is 'Canadian dollars per US dollar, set in the app. Used for new US-dollar expenses and to show the budget in US dollars.';
