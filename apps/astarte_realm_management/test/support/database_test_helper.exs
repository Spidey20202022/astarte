#
# This file is part of Astarte.
#
# Copyright 2017 Ispirata Srl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

defmodule Astarte.RealmManagement.DatabaseTestHelper do
  alias Astarte.Core.CQLUtils
  alias Astarte.Core.Device
  alias CQEx.Query, as: DatabaseQuery
  alias CQEx.Client, as: DatabaseClient
  alias CQEx.Result, as: DatabaseResult
  require Logger

  @jwt_public_key_pem """
  -----BEGIN PUBLIC KEY-----
  MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAE7u5hHn9oE9uy5JoUjwNU6rSEgRlAFh5e
  u9/f1dNImWDuIPeLu8nEiuHlCMy02+YDu0wN2U1psPC7w6AFjv4uTg==
  -----END PUBLIC KEY-----
  """

  @create_autotestrealm """
    CREATE KEYSPACE autotestrealm
      WITH
        replication = {'class': 'SimpleStrategy', 'replication_factor': '1'} AND
        durable_writes = true;
  """

  @create_interfaces_table """
      CREATE TABLE autotestrealm.interfaces (
        name ascii,
        major_version int,
        minor_version int,
        interface_id uuid,
        storage_type int,
        storage ascii,
        type int,
        ownership int,
        aggregation int,
        automaton_transitions blob,
        automaton_accepting_states blob,
        description varchar,
        doc varchar,

        PRIMARY KEY (name, major_version)
      );
  """

  @create_endpoints_table """
      CREATE TABLE autotestrealm.endpoints (
        interface_id uuid,
        endpoint_id uuid,
        interface_name ascii,
        interface_major_version int,
        interface_minor_version int,
        interface_type int,
        endpoint ascii,
        value_type int,
        reliability int,
        retention int,
        database_retention_policy int,
        database_retention_ttl int,
        expiry int,
        allow_unset boolean,
        explicit_timestamp boolean,
        description varchar,
        doc varchar,

        PRIMARY KEY ((interface_id), endpoint_id)
      );
  """

  @create_individual_properties_table """
      CREATE TABLE autotestrealm.individual_properties (
        device_id uuid,
        interface_id uuid,
        endpoint_id uuid,
        path varchar,
        reception_timestamp timestamp,
        reception_timestamp_submillis smallint,

        double_value double,
        integer_value int,
        boolean_value boolean,
        longinteger_value bigint,
        string_value varchar,
        binaryblob_value blob,
        datetime_value timestamp,
        doublearray_value list<double>,
        integerarray_value list<int>,
        booleanarray_value list<boolean>,
        longintegerarray_value list<bigint>,
        stringarray_value list<varchar>,
        binaryblobarray_value list<blob>,
        datetimearray_value list<timestamp>,

        PRIMARY KEY((device_id, interface_id), endpoint_id, path)
      )
  """

  @create_kv_store_table """
    CREATE TABLE autotestrealm.kv_store (
      group varchar,
      key varchar,
      value blob,

      PRIMARY KEY ((group), key)
    );
  """

  @create_simple_triggers_table """
      CREATE TABLE autotestrealm.simple_triggers (
        object_id uuid,
        object_type int,
        parent_trigger_id uuid,
        simple_trigger_id uuid,
        trigger_data blob,
        trigger_target blob,

        PRIMARY KEY ((object_id, object_type), parent_trigger_id, simple_trigger_id)
      );
  """

  @insert_public_key """
    INSERT INTO autotestrealm.kv_store (group, key, value)
    VALUES ('auth', 'jwt_public_key_pem', varcharAsBlob(:pem));
  """

  def seed_datastream_test_data(client, device_id, interface_name, major, endpoint_id, path) do
    interface_id = CQLUtils.interface_id(interface_name, major)

    Enum.each(
      [
        """
        INSERT INTO individual_properties
          (device_id, interface_id, endpoint_id, path)
        VALUES (:device_id, :interface_id, :endpoint_id, :path);
        """,
        """
        INSERT INTO individual_datastreams
          (device_id, interface_id, endpoint_id, path, value_timestamp, reception_timestamp, reception_timestamp_submillis, integer_value)
        VALUES (:device_id, :interface_id, :endpoint_id, '/0/integerValues', '2017-09-28 04:06+0000', '2017-09-28 05:06+0000', 0, 42);
        """
      ],
      fn statement ->
        query =
          DatabaseQuery.new()
          |> DatabaseQuery.statement(statement)
          |> DatabaseQuery.put(:device_id, device_id)
          |> DatabaseQuery.put(:interface_id, interface_id)
          |> DatabaseQuery.put(:endpoint_id, endpoint_id)
          |> DatabaseQuery.put(:path, path)

        DatabaseQuery.call!(client, query)
      end
    )

    kv_store_statement = "INSERT INTO kv_store (group, key) VALUES (:group, :key)"

    kv_query =
      DatabaseQuery.new()
      |> DatabaseQuery.statement(kv_store_statement)
      |> DatabaseQuery.put(:group, "devices-with-data-on-interface-#{interface_name}-v0")
      |> DatabaseQuery.put(:key, Device.encode_device_id(device_id))
      |> DatabaseQuery.consistency(:all)

    DatabaseQuery.call!(client, kv_query)

    :ok
  end

  def count_rows_for_datastream(client, device_id, interface_name, major, endpoint_id, path) do
    count_statement = """
    SELECT COUNT(*)
    FROM individual_datastreams
    WHERE device_id=:device_id AND interface_id=:interface_id
      AND endpoint_id=:endpoint_id AND path=:path
    """

    interface_id = CQLUtils.interface_id(interface_name, major)

    count_query =
      DatabaseQuery.new()
      |> DatabaseQuery.statement(count_statement)
      |> DatabaseQuery.put(:device_id, device_id)
      |> DatabaseQuery.put(:interface_id, interface_id)
      |> DatabaseQuery.put(:endpoint_id, endpoint_id)
      |> DatabaseQuery.put(:path, path)

    DatabaseQuery.call!(client, count_query)
    |> DatabaseResult.head()
    |> Keyword.fetch!(:count)
  end

  def seed_properties_test_value(client, device_id, interface_name, major, endpoint_id, path) do
    interface_id = CQLUtils.interface_id(interface_name, major)

    property_statement = """
    INSERT INTO individual_properties
      (device_id, interface_id, endpoint_id, path)
    VALUES (:device_id, :interface_id, :endpoint_id, :path)
    """

    query =
      DatabaseQuery.new()
      |> DatabaseQuery.statement(property_statement)
      |> DatabaseQuery.put(:device_id, device_id)
      |> DatabaseQuery.put(:interface_id, interface_id)
      |> DatabaseQuery.put(:endpoint_id, endpoint_id)
      |> DatabaseQuery.put(:path, path)

    DatabaseQuery.call!(client, query)

    kv_store_statement = "INSERT INTO kv_store (group, key) VALUES (:group, :key)"

    kv_query =
      DatabaseQuery.new()
      |> DatabaseQuery.statement(kv_store_statement)
      |> DatabaseQuery.put(:group, "devices-with-data-on-interface-#{interface_name}-v0")
      |> DatabaseQuery.put(:key, Device.encode_device_id(device_id))
      |> DatabaseQuery.consistency(:all)

    DatabaseQuery.call!(client, kv_query)

    :ok
  end

  def count_interface_properties_for_device(client, device_id, interface_name, major) do
    count_statement = """
    SELECT COUNT(*)
    FROM individual_properties
    WHERE device_id=:device_id AND interface_id=:interface_id
    """

    interface_id = CQLUtils.interface_id(interface_name, major)

    count_query =
      DatabaseQuery.new()
      |> DatabaseQuery.statement(count_statement)
      |> DatabaseQuery.put(:device_id, device_id)
      |> DatabaseQuery.put(:interface_id, interface_id)

    DatabaseQuery.call!(client, count_query)
    |> DatabaseResult.head()
    |> Keyword.fetch!(:count)
  end

  def create_test_keyspace(client) do
    DatabaseQuery.call!(client, @create_autotestrealm)
    DatabaseQuery.call!(client, @create_interfaces_table)
    DatabaseQuery.call!(client, @create_endpoints_table)
    DatabaseQuery.call!(client, @create_individual_properties_table)
    DatabaseQuery.call!(client, @create_kv_store_table)
    DatabaseQuery.call!(client, @create_simple_triggers_table)

    :ok
  end

  def seed_test_data(client) do
    Enum.each(["interfaces", "endpoints", "individual_properties", "kv_store"], fn table ->
      DatabaseQuery.call!(client, "TRUNCATE autotestrealm.#{table}")
    end)

    query =
      DatabaseQuery.new()
      |> DatabaseQuery.statement(@insert_public_key)
      |> DatabaseQuery.put(:pem, @jwt_public_key_pem)

    with {:ok, _result} <- DatabaseQuery.call(client, query) do
      :ok
    else
      error ->
        Logger.warn("Database error: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  def drop_test_keyspace(client) do
    with {:ok, _result} <- DatabaseQuery.call(client, "DROP KEYSPACE autotestrealm") do
      :ok
    else
      error ->
        Logger.warn("Database error: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  def connect_to_test_database do
    DatabaseClient.new(List.first(Application.get_env(:cqerl, :cassandra_nodes)))
  end

  def jwt_public_key_pem_fixture do
    @jwt_public_key_pem
  end
end