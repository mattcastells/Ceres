'use client';

import { useEffect, useRef, type ReactNode } from 'react';

/**
 * Un diálogo con el mismo `<dialog>` nativo y el mismo estilo del modal del
 * día (`.modal`): Escape, el foco atrapado y el fondo inerte los resuelve el
 * navegador. Reemplaza a `window.confirm`, que en un panel con tema propio se
 * ve como una ventana de otro programa.
 */
export function Dialog({
  open,
  onClose,
  title,
  children,
  locked = false,
  wide = false,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  /** Más ancho, para un formulario largo (el alta con datos). */
  wide?: boolean;
  /** Mientras corre la acción no se cierra: ni Escape ni clic afuera. Si se
   *  cerrara, el error de la acción quedaría sin mostrarse y el estado de
   *  React diría "abierto" con el diálogo cerrado. */
  locked?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      d.showModal();
      // `showModal()` le da el foco al primer control —la ✕— y pisa el
      // `autoFocus` de React, que corrió antes. Se lo devuelve a quien lo pidió.
      d.querySelector<HTMLElement>('[data-autofocus]')?.focus();
    }
    if (!open && d.open) d.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      className={wide ? 'modal modal--form modal--wide' : 'modal modal--form'}
      aria-label={title}
      onClose={onClose}
      onCancel={(e) => {
        if (locked) e.preventDefault();
      }}
      onClick={(e) => {
        if (e.target === ref.current && !locked) onClose();
      }}
    >
      {open && (
        <div className="modal-box">
          <div className="modal-data">
            <div className="modal-head">
              <h3>{title}</h3>
              <button type="button" className="modal-close" onClick={onClose} aria-label="Cerrar">
                ✕
              </button>
            </div>
            {children}
          </div>
        </div>
      )}
    </dialog>
  );
}

/** "¿Seguro?" con la acción nombrada en el botón, nunca un "Aceptar". */
export function ConfirmDialog({
  open,
  title,
  body,
  confirmLabel,
  busyLabel,
  busy = false,
  error = null,
  danger = false,
  onConfirm,
  onClose,
}: {
  open: boolean;
  title: string;
  body: ReactNode;
  confirmLabel: string;
  busyLabel?: string;
  busy?: boolean;
  error?: string | null;
  danger?: boolean;
  onConfirm: () => void;
  onClose: () => void;
}) {
  return (
    <Dialog open={open} onClose={onClose} title={title} locked={busy}>
      <div className="muted" style={{ margin: 0 }}>{body}</div>
      {error && <p className="form-error" style={{ margin: 0 }}>{error}</p>}
      <div className="row dialog-actions">
        <button type="button" className="button--quiet" onClick={onClose} disabled={busy}>
          Cancelar
        </button>
        <button
          type="button"
          className={danger ? 'button--danger' : 'button--primary'}
          onClick={onConfirm}
          disabled={busy}
          data-autofocus
        >
          {busy ? (busyLabel ?? `${confirmLabel}…`) : confirmLabel}
        </button>
      </div>
    </Dialog>
  );
}
