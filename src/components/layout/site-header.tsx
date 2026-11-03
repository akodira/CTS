import { getTranslations } from 'next-intl/server';
import { Link } from '@/i18n/navigation';
import { LocaleSwitcher } from './locale-switcher';

export async function SiteHeader() {
  const t = await getTranslations('Header');

  return (
    <header className="sticky top-0 z-40 border-b border-border bg-background/85 backdrop-blur">
      <div className="mx-auto flex h-16 w-full max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        <Link
          href="/"
          className="flex min-w-0 items-center gap-3 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        >
          <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-brand text-[0.7rem] font-bold tracking-wide text-white">
            {t('brandShort')}
          </span>
          <span className="truncate text-sm font-semibold tracking-tight">
            {t('brand')}
          </span>
        </Link>

        <LocaleSwitcher />
      </div>
    </header>
  );
}
