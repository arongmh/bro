##! Base Modbus analysis script.

module Modbus;

export {
	redef enum Log::ID += { LOG };

	type Info: record {
		## Time of the request.
		ts:        time           &log;
		## Unique identifier for the connnection.
		uid:       string         &log;
		## Identifier for the connection.
		id:        conn_id        &log;
		## The name of the function message that was sent.
		func:      string         &log &optional;
		## The status of the response.
		success:   bool           &log &default=T;
		## The exception if the response was a failure.
		exception: string         &log &optional;
	};

	## Event that can be handled to access the Modbus record as it is sent on 
	## to the logging framework.
	global log_modbus: event(rec: Info);
}

redef record connection += {
	modbus: Info &optional;
};

# Configure DPD and the packet filter.
redef capture_filters += { ["modbus"] = "tcp port 502" };
redef dpd_config += { [ANALYZER_MODBUS] = [$ports = set(502/tcp)] };
redef likely_server_ports += { 502/tcp };

event bro_init() &priority=5
	{
	Log::create_stream(Modbus::LOG, [$columns=Info, $ev=log_modbus]);
	}

event modbus_message(c: connection, headers: ModbusHeaders, is_orig: bool) &priority=5
	{
	if ( ! c?$modbus )
		{
		c$modbus = [$ts=network_time(), $uid=c$uid, $id=c$id];
		}

	c$modbus$ts   = network_time();
	c$modbus$func = function_codes[headers$function_code];

	if ( ! is_orig && 
	     ( headers$function_code >= 0x81 || headers$function_code <= 0x98 ) )
		c$modbus$success = F;
	else
		c$modbus$success = T;
	}

event modbus_message(c: connection, headers: ModbusHeaders, is_orig: bool) &priority=-5
	{
	# Don't log now if this is an exception (log in the exception event handler)
	if ( c$modbus$success )
		Log::write(LOG, c$modbus);
	}

event modbus_exception(c: connection, headers: ModbusHeaders, code: count) &priority=5
	{
	c$modbus$exception = exception_codes[code];
	Log::write(LOG, c$modbus);

	delete c$modbus$exception;
	}

