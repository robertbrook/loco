
#ifndef LOCO_PRIMITIVES_H
#define LOCO_PRIMITIVES_H
#include "interp.h"
void register_data_primitives(Interp *interp);
void register_arith_primitives(Interp *interp);
void register_logic_primitives(Interp *interp);
void register_comm_primitives(Interp *interp);
void register_file_primitives(Interp *interp);
void register_ctrl_primitives(Interp *interp);
void register_ws_primitives(Interp *interp);
void register_tmpl_primitives(Interp *interp);
#define REG(name, min, def, max, fn) \
    ws_define(&interp->ws, make_primitive(name, min, def, max, fn))
#define CHECK_WORD(v, name) \
    if (!(v) || (v)->type != LV_WORD) interp_error(interp, "%s requires a word", name)
#define CHECK_NUM(v, name) \
    if (!logo_is_number(v)) interp_error(interp, "%s requires a number", name)
#define CHECK_LIST(v, name) \
    if ((v) && (v)->type == LV_ARRAY) interp_error(interp, "%s requires a list (not array)", name)
#endif
