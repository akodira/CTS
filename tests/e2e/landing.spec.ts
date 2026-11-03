import { expect, test } from '@playwright/test';

test.describe('public shell', () => {
  test('renders the English landing page in LTR', async ({ page }) => {
    await page.goto('/en');

    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    await expect(page.locator('html')).toHaveAttribute('dir', 'ltr');
    await expect(
      page.getByRole('heading', { level: 1 }),
    ).toContainText('Support that moves at your pace.');

    await expect(
      page.getByRole('link', { name: 'Check system health' }),
    ).toHaveAttribute('href', '/api/health');
  });

  test('renders the Arabic landing page in RTL', async ({ page }) => {
    await page.goto('/ar');

    await expect(page.locator('html')).toHaveAttribute('lang', 'ar');
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
    await expect(
      page.getByRole('heading', { level: 1 }),
    ).toContainText('دعم يسير بالوتيرة التي تناسبك.');
  });

  test('switches between Arabic and English without leaving the page', async ({
    page,
  }) => {
    await page.goto('/en');
    await page.getByRole('button', { name: 'Switch language' }).click();

    await page.waitForURL('**/ar');
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');

    await page.getByRole('button', { name: 'تغيير اللغة' }).click();
    await page.waitForURL('**/en');
    await expect(page.locator('html')).toHaveAttribute('dir', 'ltr');
  });

  test('reports health as JSON', async ({ request }) => {
    const response = await request.get('/api/health');
    const body = await response.json();

    expect([200, 503]).toContain(response.status());
    expect(body).toHaveProperty('status');
    expect(body).toHaveProperty('checks');
    expect(typeof body.checks.environment).toBe('boolean');
    expect(typeof body.checks.database).toBe('boolean');
  });
});
