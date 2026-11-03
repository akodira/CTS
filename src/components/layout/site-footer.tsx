import { getTranslations } from 'next-intl/server';

export async function SiteFooter() {
  const t = await getTranslations('Footer');
  const year = new Date().getFullYear();

  return (
    <footer className="border-t border-border">
      <div className="mx-auto flex w-full max-w-6xl flex-col gap-3 px-4 py-8 text-xs text-muted sm:flex-row sm:items-center sm:justify-between sm:px-6">
        <p>
          © {year} {t('rights')}
        </p>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <span>{t('note')}</span>
          {/* This points at a Route Handler, not a page, so client-side
              navigation and prefetching do not apply. */}
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a
            href="/api/health"
            className="rounded underline decoration-border underline-offset-4 transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand"
          >
            {t('healthLink')}
          </a>
        </div>
      </div>
    </footer>
  );
}
