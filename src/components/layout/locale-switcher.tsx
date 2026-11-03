'use client';

import { Languages } from 'lucide-react';
import { useLocale, useTranslations } from 'next-intl';
import { useTransition } from 'react';
import { usePathname, useRouter } from '@/i18n/navigation';
import { routing, type Locale } from '@/i18n/routing';

export function LocaleSwitcher() {
  const locale = useLocale() as Locale;
  const t = useTranslations('Header');
  const pathname = usePathname();
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  const nextLocale: Locale =
    routing.locales.find((candidate) => candidate !== locale) ?? locale;

  function switchLocale() {
    startTransition(() => {
      router.replace(pathname, { locale: nextLocale });
    });
  }

  return (
    <button
      type="button"
      onClick={switchLocale}
      disabled={isPending || nextLocale === locale}
      aria-label={t('switchLanguage')}
      className="inline-flex h-9 items-center gap-2 rounded-full border border-border bg-surface px-3 text-xs font-medium text-foreground transition-colors hover:bg-surface-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:opacity-60"
    >
      <Languages className="size-4 text-brand" aria-hidden="true" />
      <span>{nextLocale === 'ar' ? t('arabic') : t('english')}</span>
    </button>
  );
}
