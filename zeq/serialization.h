
/* Copyright (c) 2014, Human Brain Project
 *                     Daniel Nachbaur <daniel.nachbaur@epfl.ch>
 */

#ifndef ZEQ_SERIALIZATION_H
#define ZEQ_SERIALIZATION_H

#include <zeq/types.h>

namespace zeq
{

enum MessageType
{
    MSG_CAMERA,
    MSG_SELECTION,
    MSG_INVALID
};

Event serializeCamera( const std::vector< float >& matrix );
std::vector< float > deserializeCamera( const Event& camera );

Event serializeSelection( const std::vector< unsigned int >& selection );
std::vector< unsigned int > deserializeSelection( const Event& selection );

}

#endif
