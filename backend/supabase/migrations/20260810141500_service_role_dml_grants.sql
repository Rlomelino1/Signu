
grant select, insert, update, delete on
  public.profiles,
  public.connection,
  public.bank_account,
  public.transaction,
  public.subscription,
  public.subscription_run,
  public.charge
  to service_role;

