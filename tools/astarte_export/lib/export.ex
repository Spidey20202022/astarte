#
# This file is part of Astarte.
#
# Copyright 2019 Ispirata Srl
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

defmodule Astarte.Export do
  alias Astarte.Export.FetchData
  require Logger

  @moduledoc """
    This  module provide API functions to export realm device 
    data in a xml format. This data can be used by astarte_import 
    application utlity  to import into a new realm.
  """
  
  @doc """
  The export_realm_data/2 function required 2 arguments to export 
  the realm data into XML format.
  the arguments are
   -realm-name -> This is a string format of input
   - path      -> path where to export the realm file.

  @spec export_realm_data(String.t, String.t) :: :ok | {:error, :invalid_parameters} | {:error, reason}

  """

  def export_realm_data(realm, path) do
    with true <- File.dir?(path) do
      timestamp = format_time
      filename = path <> "/" <> realm <> "_" <> timestamp <> ".xml"
      generate_xml(realm, filename)
    else
      result -> {:error, :invalid_parameters}
    end
  end

  defp write_to_file(file_descriptor, xml_data) do
    with :ok <- IO.puts(file_descriptor, xml_data) do
      :ok
    else
      reason -> {:error, reason}
    end
  end

  def generate_xml(realm, file) do
    with {:ok, file_descriptor} = File.open(file, [:write]),
         Logger.info("Export started.", realm: realm),
         {:ok, :finished} <- generate_xml_1(realm, file_descriptor, []) do
      Logger.info("Export completed into file: #{file}", realm: realm)
      File.close(file_descriptor)
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_xml_1(realm, file_descriptor, opts) do
    with {:more_data, device_data, updated_options} <- FetchData.fetch_device_data(realm, opts),
         {:ok, xml_data} <- serialize_to_xml(device_data),
         :ok <- IO.puts(file_descriptor, "xml_data") do
      generate_xml_1(realm, file_descriptor, updated_options)
    else
      {:ok, :completed} ->
        tags = astarte_default_close_tags()
        IO.puts(file_descriptor, tags)
        {:ok, :finished}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def serialize_to_xml(device_data) do
    xml_data =
      serialize_xml(:device, device_data)
      |> XmlBuilder.generate()
      |> XmlBuilder.document()
      |> XmlBuilder.generate()

    {:ok, xml_data}
  end


  @spec serialize_xml(atom(), struct() | keyword()) :: {atom(), map(), String.t() | keyword()}

  def serialize_xml(tag, options) do
    {tag, get_attributes(tag, options), get_value(tag, options)}
  end


  @spec get_attributes(atom(), struct() | keyword()) :: map()

  defp get_attributes(:device, state) do
    %{device_id: state.device_id}
  end

  defp get_attributes(:protocol, state) do
    %{revision: state.revision, 
	  pending_empty_cache: state.pending_empty_cache}
  end

  defp get_attributes(:registration, state) do
    %{
      secret_bcrypt_hash: state.secret_bcrypt_hash,
      first_registration: state.first_registration
    }
  end

  defp get_attributes(:credentials, state) do
    %{
      inhibit_request: state.inhibit_request,
      cert_serial: state.cert_serial,
      cert_aki: state.cert_aki,
      first_credentials_request: state.first_credentials_request
    }
  end

  defp get_attributes(:stats, state) do
    %{
      total_received_msgs: state.total_received_msgs,
      total_received_bytes: state.total_received_bytes,
      last_connection: state.last_connection,
      last_disconnection: state.last_disconnection,
      last_seen_ip: state.last_seen_ip
    }
  end

  defp get_attributes(:interfaces, state) do
    %{}
  end

  defp get_attributes(:interface, state) do
    %{
      name: state.interface_name,
      major_version: state.major_version,
      minor_version: state.minor_version,
      active: state.active
    }
  end

  defp get_attributes(:datastream, {_type, state}) do
    %{path: state.path}
  end

  defp get_attributes(:property, state) do
    %{path: state.path, reception_timestamp: state.reception_timestamp}
  end

  defp get_attributes(:object, state) do
    %{reception_timestamp: state.reception_timestamp}
  end

  defp get_attributes(:value, state) do
    %{:reception_timestamp => state[:reception_timestamp]}
  end

  defp get_attributes(:item, value) do
    %{name: value.path}
  end

  defp get_attributes(_tag, _value) do
    %{}
  end


  @spec get_value(atom(), struct() | keyword()) ::
          String.t()
          | charlist()
          | maybe_improper_list()

  defp get_value(:device, state) do
    tag_list = [:protocol, :registration, :credentials, :stats, :interfaces]

    Enum.reduce(tag_list, [], fn tag, acc ->
      acc ++ [serialize_xml(tag, state)]
    end)
  end

  defp get_value(:interfaces, state) do
    Enum.reduce(state.interfaces, [], fn interface_state, acc ->
      acc ++ [serialize_xml(:interface, interface_state)]
    end)
  end

  defp get_value(:interface, state) do
    mappings = state.mappings
    interface_type = state.interface_type

    Enum.reduce(mappings, [], fn mapping, acc ->
      case interface_type do
        {:datastream, _} ->
          acc ++ [serialize_xml(:datastream, mapping)]
        {:properties, _} ->
          acc ++ [serialize_xml(:property, mapping)]
      end
    end)
  end

  defp get_value(:datastream, mapping) do
    Enum.reduce(mapping.value, [], fn value, acc ->
      output =
        case mapping.aggregation do
          :object ->
            serialize_xml(:object, value)
          :individual ->
            serialize_xml(:value, value)
        end
      acc ++ [output]
    end)
  end

  defp get_value(:object, value) do
    [serialize_xml(:item, value)]
  end

  defp get_value(:property, value) do
    value[:double_value] |> Kernel.to_string()
  end

  defp get_value(:value, value) do
    value[:double_value] |> Kernel.to_string()
  end

  defp get_value(tag, _values) do
    ""
  end

  def format_time() do
    {{year, month, date}, {hour, minute, second}} = :calendar.local_time()

    to_string(year) <>
      "_" <>
      to_string(month) <>
      "_" <>
      to_string(date) <>
      "_" <>
      to_string(hour) <>
      "_" <>
      to_string(minute) <>
      "_" <>
      to_string(second)
  end

  defp default_xml_header() do
    XmlBuilder.document("")
    |> XmlBuilder.generate()
  end

  defp astarte_default_open_tags do
    "<astarte>\n<devices>\n"
  end

  defp astarte_default_close_tags do
    "</devices>\n</astarte>"
  end
end
