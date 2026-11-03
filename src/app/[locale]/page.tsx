import { getTranslations } from 'next-intl/server';
import {
  Check,
  Circle,
  Database,
  Globe2,
  LifeBuoy,
  MessagesSquare,
  Rocket,
  ShieldCheck,
} from 'lucide-react';
import { SiteFooter } from '@/components/layout/site-footer';
import { SiteHeader } from '@/components/layout/site-header';

const featureIcons = [LifeBuoy, MessagesSquare, Globe2];
const statusIcons = [Check, Check, Check, Circle];

export default async function HomePage() {
  const t = await getTranslations('Home');

  const features = [
    {
      title: t('portalTitle'),
      body: t('portalBody'),
    },
    {
      title: t('consoleTitle'),
      body: t('consoleBody'),
    },
    {
      title: t('bilingualTitle'),
      body: t('bilingualBody'),
    },
  ];

  const statusItems = [
    t('statusItems.app'),
    t('statusItems.schema'),
    t('statusItems.security'),
    t('statusItems.deploy'),
  ];

  return (
    <div className="flex min-h-dvh flex-col">
      <SiteHeader />

      <main id="main-content" className="flex-1">
        <section className="relative overflow-hidden border-b border-border">
          <div
            aria-hidden="true"
            className="pointer-events-none absolute -top-32 end-[-10rem] size-[34rem] rounded-full bg-brand-soft blur-3xl"
          />
          <div
            aria-hidden="true"
            className="pointer-events-none absolute bottom-[-16rem] start-[-12rem] size-[30rem] rounded-full bg-surface-muted blur-3xl"
          />

          <div className="relative mx-auto w-full max-w-6xl px-4 py-20 sm:px-6 lg:py-28">
            <div className="max-w-3xl">
              <span className="rise inline-flex items-center gap-2 rounded-full border border-border bg-surface px-3 py-1 text-xs font-medium text-muted">
                <span className="size-1.5 rounded-full bg-brand" />
                {t('badge')}
              </span>

              <h1 className="rise rise-delay-1 mt-6 text-balance text-4xl font-semibold leading-[1.1] tracking-tight sm:text-5xl lg:text-6xl">
                {t('title')}
              </h1>

              <p className="rise rise-delay-2 mt-5 max-w-2xl text-pretty text-base leading-7 text-muted sm:text-lg">
                {t('subtitle')}
              </p>
            </div>

            <div className="mt-14 grid gap-4 md:grid-cols-3">
              {features.map((feature, index) => {
                const Icon = featureIcons[index];
                return (
                  <article
                    key={feature.title}
                    className={`rise rise-delay-${index + 1} rounded-2xl border border-border bg-surface p-6 shadow-[0_1px_0_rgba(15,23,42,0.03)]`}
                  >
                    <span className="grid size-10 place-items-center rounded-xl bg-brand-soft text-brand">
                      <Icon className="size-5" aria-hidden="true" />
                    </span>
                    <h2 className="mt-5 text-base font-semibold tracking-tight">
                      {feature.title}
                    </h2>
                    <p className="mt-2 text-sm leading-6 text-muted">
                      {feature.body}
                    </p>
                  </article>
                );
              })}
            </div>
          </div>
        </section>

        <section className="mx-auto w-full max-w-6xl px-4 py-16 sm:px-6">
          <div className="grid gap-8 lg:grid-cols-[0.9fr_1.1fr] lg:items-start">
            <div>
              <span className="inline-flex size-11 items-center justify-center rounded-2xl border border-border bg-surface text-brand">
                <Rocket className="size-5" aria-hidden="true" />
              </span>
              <h2 className="mt-5 text-2xl font-semibold tracking-tight sm:text-3xl">
                {t('statusTitle')}
              </h2>
              <p className="mt-3 max-w-xl text-sm leading-7 text-muted">
                {t('statusBody')}
              </p>

              <div className="mt-6 rounded-2xl border border-border bg-surface p-5">
                <p className="text-xs font-semibold uppercase tracking-[0.14em] text-brand">
                  {t('plannedTitle')}
                </p>
                <p className="mt-2 text-sm leading-6 text-muted">
                  {t('plannedBody')}
                </p>
              </div>
            </div>

            <ul className="divide-y divide-border overflow-hidden rounded-2xl border border-border bg-surface">
              {statusItems.map((item, index) => {
                const Icon = statusIcons[index];
                const done = index < 3;
                return (
                  <li
                    key={item}
                    className="flex items-start gap-4 p-5 sm:p-6"
                  >
                    <span
                      className={`mt-0.5 grid size-7 shrink-0 place-items-center rounded-full ${
                        done
                          ? 'bg-brand-soft text-brand'
                          : 'bg-surface-muted text-muted'
                      }`}
                    >
                      <Icon className="size-4" aria-hidden="true" />
                    </span>
                    <div>
                      <p className="text-sm leading-6">{item}</p>
                      <span className="sr-only">
                        {done ? 'Complete' : 'Pending'}
                      </span>
                    </div>
                  </li>
                );
              })}
            </ul>
          </div>

          <div className="mt-10 flex flex-wrap items-center gap-3 text-xs text-muted">
            <ShieldCheck className="size-4 text-brand" aria-hidden="true" />
            <span>RLS</span>
            <span aria-hidden="true">·</span>
            <Database className="size-4 text-brand" aria-hidden="true" />
            <span>PostgreSQL</span>
            <span aria-hidden="true">·</span>
            <Globe2 className="size-4 text-brand" aria-hidden="true" />
            <span>EN / AR</span>
          </div>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}
