import { CdkDragStart } from '@angular/cdk/drag-drop';

/**
 * The CDK drag preview of a table row is a clone laid out on its own, so its
 * cells lose the table's column widths. Copy the header cell widths onto the
 * preview so it looks like the row being moved. By the time `started` fires
 * the source row has been moved out of the table, so find the table through
 * the placeholder that took its place.
 */
export function keepRowWidths(e: CdkDragStart): void {
  const head = e.source.getPlaceholderElement().closest('table')?.querySelector('thead tr');
  const preview = e.source.element.nativeElement.ownerDocument.querySelector<HTMLElement>('tr.cdk-drag-preview');
  if (!head || !preview) return;
  preview.style.width = `${head.getBoundingClientRect().width}px`;
  Array.from(head.children).forEach((th, i) => {
    const td = preview.children[i] as HTMLElement | undefined;
    if (td) td.style.width = td.style.minWidth = td.style.maxWidth = `${th.getBoundingClientRect().width}px`;
  });
}
