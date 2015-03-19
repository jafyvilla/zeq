
/* Copyright (c) 2015, Human Brain Project
 *                     grigori.chevtchenko@epfl.ch
 */


#ifndef ZEQ_EVENTDESCRIPTOR_H
#define ZEQ_EVENTDESCRIPTOR_H

#include <zeq/api.h>

#include <zeq/types.h>
#include <boost/noncopyable.hpp>

namespace zeq
{
namespace detail { struct EventDescriptor; }

/**
 * This structure holds informations about an Event from a vocabulary.
 * It contains the REST api name, the 128bit zeq event id and the schema
 * needed for automatic JSON serialization/deserialization.
 */
struct EventDescriptor : public boost::noncopyable
{
    /**
     * Create an EventDescriptor.
     * @param restName the string used for REST command
     * @param eventType the zeq event's uint128
     * @param schema the flatbuffers schema as string
     */
    ZEQ_API EventDescriptor( const std::string& restName, const lunchbox::uint128_t& eventType,
                             const std::string& schema );

    /** Move ctor @internal */
    ZEQ_API EventDescriptor( EventDescriptor&& rhs );

    ~EventDescriptor();

    /** @return the REST command string of this event */
    ZEQ_API const std::string& getRestName() const;

    /** @return the zeq event's uint128 */
    ZEQ_API const lunchbox::uint128_t& getEventType() const;

    /** @return the flatbuffers schema string*/
    ZEQ_API const std::string& getSchema() const;
private:

    EventDescriptor& operator=( EventDescriptor&& rhs );

    detail::EventDescriptor* _impl;
};

}

#endif