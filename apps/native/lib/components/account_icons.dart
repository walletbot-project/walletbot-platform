import 'package:flutter/material.dart';

/// Icon catalog for accounts. Mirrors the shape of `color_utils`: a default
/// plus a curated option list the icon picker renders. Prototype-only visuals
/// (the backend stores an icon name, not an `IconData`).
const IconData accountDefaultIcon = Icons.account_balance_wallet_rounded;

const accountIconOptions = <IconData>[
  accountDefaultIcon,
  Icons.account_balance_rounded,
  Icons.savings_rounded,
  Icons.payments_rounded,
  Icons.credit_card_rounded,
  Icons.flight_takeoff_rounded,
  Icons.trending_up_rounded,
  Icons.attach_money_rounded,
  Icons.currency_exchange_rounded,
  Icons.real_estate_agent_rounded,
  Icons.wallet_rounded,
];
