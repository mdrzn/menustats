// Accesso a sensori e SMC tramite API private di IOKit (usate anche da altri monitor open source).
// Possono smettere di funzionare con un aggiornamento di macOS: chi le usa deve gestire l'assenza di dati.
#ifndef MSUPPORT_H
#define MSUPPORT_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

// Temperature: array di dizionari { "name": CFString, "value": CFNumber (°C) }. NULL se non disponibili.
CFArrayRef _Nullable ms_copy_temperatures(void) CF_RETURNS_RETAINED;

// SMC: apertura una tantum; 0 = ok
int ms_smc_open(void);
void ms_smc_close(void);
// Legge una chiave numerica a 4 caratteri (flt, fpe2, ui8/16/32, sp78…). Ritorna 0 se ok.
int ms_smc_read_number(const char * _Nonnull key, double * _Nonnull out);

#endif
